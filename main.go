package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"filippo.io/age"
	"filippo.io/age/armor"
	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	"github.com/alecthomas/kong"
)

type AgeFsFile struct {
	fs.Inode
	Data []byte
}

var CLI struct {
	MetaFile   string   `help:"Path to metadata file that specifies which files to present" arg:""`
	MountPoint string   `help:"Mount point where unencrypted files will be available" arg:""`
	Identity   []string `help:"Path to one or more identity files" short:"i" required:""`
	Debug      bool     `help:"Enable debug mode"`
	Options    []string `help:"Options to pass to the mount point" short:"o"`
}

var _ = (fs.FileReader)((*AgeFsFile)(nil))

func (f *AgeFsFile) Read(ctx context.Context, dest []byte, off int64) (fuse.ReadResult, syscall.Errno) {
	end := off + int64(len(dest))
	if end > int64(len(f.Data)) {
		end = int64(len(f.Data))
	}

	return fuse.ReadResultData(f.Data[off:end]), fs.OK
}

type AgeFsNode struct {
	fs.Inode
	Root      *AgeFsRoot
	Meta      Meta
	Data      []byte
	Decrypted []byte
	Armored   bool
}

var _ = (fs.NodeOpener)((*AgeFsNode)(nil))
var _ = (fs.NodeGetattrer)((*AgeFsNode)(nil))

func (n *AgeFsNode) Open(ctx context.Context, flags uint32) (fh fs.FileHandle, fuseFlags uint32, errno syscall.Errno) {
	// disallow writes
	if flags&(syscall.O_RDWR|syscall.O_WRONLY) != 0 {
		return nil, 0, syscall.EROFS
	}

	if n.Data == nil {
		contents, err := os.ReadFile(n.Meta.File)
		if err != nil {
			return nil, 0, syscall.EIO
		}
		n.Data = contents
		n.Armored = strings.HasPrefix(string(n.Data), armor.Header)
	}

	if n.Decrypted == nil {
		var reader io.Reader = bytes.NewBuffer(n.Data)
		if n.Armored {
			reader = armor.NewReader(reader)
		}

		log.Printf("Decrypting %s\n", n.Meta.File)
		decrypted, err := age.Decrypt(reader, n.Root.Identities...)

		if err != nil {
			log.Printf("[ERROR] age.Decrypt: %v\n", err)
			return nil, 0, syscall.EIO
		}

		data, err := io.ReadAll(decrypted)
		if err != nil {
			log.Printf("[ERROR] io.ReadAll: %v\n", err)
			return nil, 0, syscall.EIO
		}
		n.Decrypted = data
	}

	fh = &AgeFsFile{Data: n.Decrypted}

	//return fh, fuse.FOPEN_KEEP_CACHE, fs.OK

	// disable kernel cache:
	return fh, fuse.FOPEN_DIRECT_IO, fs.OK
}

func (n *AgeFsNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	out.Mode = *n.Meta.Mode

	var uid uint32 = n.Root.Uid
	if n.Meta.Owner != nil {
		uid = *n.Meta.Owner
	}
	out.Owner.Uid = uid

	var gid uint32 = n.Root.Gid
	if n.Meta.Group != nil {
		gid = *n.Meta.Group
	}
	out.Owner.Gid = gid

	return fs.OK
}

//func WalkDir(ctx context.Context, root *AgeFsRoot, parent *fs.Inode, path string) error {
//	entries, err := os.ReadDir(path)
//	if err != nil {
//		return err
//	}
//
//	for _, entry := range entries {
//		path := filepath.Join(path, entry.Name())
//		if entry.IsDir() {
//			parent := parent.NewPersistentInode(ctx, &fs.Inode{}, fs.StableAttr{Mode: fuse.S_IFDIR})
//			return WalkDir(ctx, root, parent, path)
//		} else {
//			info, err := entry.Info()
//			if err != nil {
//				return fmt.Errorf("while walking %s: %v", path, err)
//			}
//
//			node := &AgeFsNode{Root: root, Path: path, Mode: info.Mode()}
//			child := parent.NewPersistentInode(ctx, node, fs.StableAttr{Mode: fuse.S_IFREG})
//			parent.AddChild(entry.Name(), child, false)
//		}
//	}
//
//	return nil
//}

type AgeFsRoot struct {
	fs.Inode
	Identities []age.Identity
	Files      []Meta
	Uid        uint32
	Gid        uint32
}

var _ = (fs.NodeOnAdder)((*AgeFsRoot)(nil))

func (root *AgeFsRoot) OnAdd(ctx context.Context) {
	for _, file := range root.Files {
		dir, name := filepath.Split(filepath.Clean(file.Name))
		parent := &root.Inode

		for _, component := range strings.Split(dir, "/") {
			if component == "" {
				continue
			}
			inode := parent.GetChild(component)
			if inode == nil {
				inode = parent.NewPersistentInode(ctx, &fs.Inode{}, fs.StableAttr{Mode: fuse.S_IFDIR})
				parent.AddChild(component, inode, false)
			}
			parent = inode
		}

		node := &AgeFsNode{Root: root, Meta: file}
		child := parent.NewPersistentInode(ctx, node, fs.StableAttr{Mode: fuse.S_IFREG})
		parent.AddChild(name, child, false)
	}

	//err := WalkDir(ctx, root, &root.Inode, root.Dir)
	//if err != nil {
	//	log.Fatalf("error while walking directory: %v\n", err)
	//}
}

type Meta struct {
	Name  string
	File  string
	Mode  *uint32
	Owner *uint32
	Group *uint32
}

func main() {
	var cli = CLI
	_ = kong.Parse(&cli)

	data, err := os.ReadFile(cli.MetaFile)
	if err != nil {
		log.Fatal(err)
	}

	var files []Meta
	err = json.Unmarshal(data, &files)
	if err != nil {
		log.Fatal(err)
	}

	var identities []age.Identity

	for _, path := range cli.Identity {
		log.Printf("Loading identities from path '%s'\n", path)
		newIdentities, err := readFileIdentities(path)
		if err != nil {
			log.Printf("[WARN] Failed to load identity file %s: %s\n", path, err)
			continue
		}
		identities = append(identities, newIdentities...)
	}

	log.Printf("Loaded %d identities\n", len(identities))
	log.Printf("Mounting filesystem at '%s'\n", cli.MountPoint)

	opts := &fs.Options{}
	opts.AllowOther = true
	opts.Debug = cli.Debug
	opts.Options = append(cli.Options, "nobrowse")

	uid := uint32(os.Getuid())
	gid := uint32(os.Getgid())
	root := &AgeFsRoot{Identities: identities, Files: files, Uid: uid, Gid: gid}

	server, err := fs.Mount(cli.MountPoint, root, opts)
	if err != nil {
		log.Fatalf("Mount fail: %v\n", err)
	}
	server.Wait()
}
