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
	"time"

	"filippo.io/age"
	"filippo.io/age/armor"
	"github.com/alecthomas/kong"
	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
	"github.com/sevlyar/go-daemon"
)

type AgeFsFile struct {
	fs.Inode
	Data []byte
}

var CLI struct {
	MetaFile   string   `help:"Path to metadata file that specifies which files to present" arg:""`
	MountPoint string   `help:"Mount point where unencrypted files will be available" arg:""`
	Options    []string `help:"Options to pass to the mount point" short:"o"`
	Foreground bool     `help:"Run in foreground" short:"f"`
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

var _ = (fs.NodeUnlinker)((*AgeFsNode)(nil))
var _ = (fs.NodeRmdirer)((*AgeFsNode)(nil))
var _ = (fs.NodeOpener)((*AgeFsNode)(nil))
var _ = (fs.NodeGetattrer)((*AgeFsNode)(nil))

func (n *AgeFsNode) Unlink(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

func (n *AgeFsNode) Rmdir(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

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

	var contents = n.Decrypted

	if contents == nil {
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
		contents = data
	}

	fh = &AgeFsFile{Data: contents}

	if n.Root.KeepCached {
		n.Decrypted = contents
		return fh, fuse.FOPEN_KEEP_CACHE, fs.OK
	} else {
		return fh, fuse.FOPEN_DIRECT_IO, fs.OK
	}
}

func (n *AgeFsNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	out.Mode = *n.Meta.Mode

	var uid = n.Root.Uid
	if n.Meta.Owner != nil {
		uid = *n.Meta.Owner
	}
	out.Owner.Uid = uid

	var gid = n.Root.Gid
	if n.Meta.Group != nil {
		gid = *n.Meta.Group
	}
	out.Owner.Gid = gid

	return fs.OK
}

type AgeFsDir struct {
	fs.Inode
}

var _ = (fs.NodeUnlinker)((*AgeFsDir)(nil))
var _ = (fs.NodeRmdirer)((*AgeFsDir)(nil))

func (d *AgeFsDir) Unlink(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

func (d *AgeFsDir) Rmdir(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

type AgeFsRoot struct {
	fs.Inode
	Identities []age.Identity
	Files      []Meta
	Uid        uint32
	Gid        uint32
	KeepCached bool
}

var _ = (fs.NodeUnlinker)((*AgeFsRoot)(nil))
var _ = (fs.NodeRmdirer)((*AgeFsRoot)(nil))
var _ = (fs.NodeOnAdder)((*AgeFsRoot)(nil))

func (root *AgeFsRoot) Unlink(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

func (root *AgeFsRoot) Rmdir(ctx context.Context, name string) syscall.Errno {
	return syscall.EROFS
}

func (root *AgeFsRoot) OnAdd(ctx context.Context) {
	marker := root.NewPersistentInode(ctx, &fs.MemRegularFile{}, fs.StableAttr{Mode: fuse.S_IFREG})
	root.AddChild(".agefs", marker, false)

	for _, file := range root.Files {
		dir, name := filepath.Split(filepath.Clean(file.Name))
		parent := &root.Inode

		for _, component := range strings.Split(dir, "/") {
			if component == "" {
				continue
			}
			inode := parent.GetChild(component)
			if inode == nil {
				inode = parent.NewPersistentInode(ctx, &AgeFsDir{}, fs.StableAttr{Mode: fuse.S_IFDIR})
				parent.AddChild(component, inode, false)
			}
			parent = inode
		}

		node := &AgeFsNode{Root: root, Meta: file}
		child := parent.NewPersistentInode(ctx, node, fs.StableAttr{Mode: fuse.S_IFREG})
		parent.AddChild(name, child, false)
	}
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

	identitiesPaths := make([]string, 0)
	keepCached := false

	opts := &fs.Options{}

	for _, options := range cli.Options {
		for _, option := range strings.Split(options, ",") {
			switch {
			case strings.HasPrefix(option, "identity="):
				identitiesPaths = append(identitiesPaths, option[len("identity="):])
			case option == "debug":
				opts.Debug = true
			case option == "allow_other":
				opts.AllowOther = true
			case option == "keep_cached":
				keepCached = true
			default:
				opts.Options = append(opts.Options, option)
			}
		}
	}

	if len(identitiesPaths) == 0 {
		log.Fatal("At least one identity file must be specified using identity=... option")
	}

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

	for _, path := range identitiesPaths {
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

	if !cli.Foreground {
		ctx := new(daemon.Context)
		child, err := ctx.Reborn()

		if err != nil {
			log.Fatal(err)
		}

		if child != nil {
			for {
				log.Println("Waiting for mountpoint to be created...")
				_, err := os.Stat(cli.MountPoint + "/.agefs")
				if err == nil {
					break
				} else {
					time.Sleep(500 * time.Millisecond)
				}
			}
			log.Println("Done")
			return
		}
	}

	uid := uint32(os.Getuid())
	gid := uint32(os.Getgid())
	root := &AgeFsRoot{Identities: identities, Files: files, Uid: uid, Gid: gid, KeepCached: keepCached}

	server, err := fs.Mount(cli.MountPoint, root, opts)
	if err != nil {
		log.Fatalf("Mount fail: %v\n", err)
	}

	server.Wait()
}
