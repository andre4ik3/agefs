package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"filippo.io/age"
	"filippo.io/age/agessh"
	"filippo.io/age/plugin"
)

func readFileIdentities(path string) ([]age.Identity, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}

	defer f.Close()

	reader := bufio.NewReader(f)

	data, err := reader.Peek(14)
	if err != nil {
		return nil, err
	}

	peeked := string(data)

	switch {
	case strings.HasPrefix(peeked, "-----BEGIN"):
		identity, err := readSSHIdentity(reader)
		if err != nil {
			return nil, fmt.Errorf("failed to parse SSH identity\n")
		}
		return []age.Identity{identity}, nil
	default:
		return readLineIdentities(reader)
	}
}

func readSSHIdentity(f io.Reader) (age.Identity, error) {
	data, err := io.ReadAll(f)
	if err != nil {
		return nil, err
	}

	return agessh.ParseIdentity(data)
}

func readLineIdentities(f io.Reader) ([]age.Identity, error) {
	var identities []age.Identity
	scanner := bufio.NewScanner(f)

	var lineNumber = 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())

		var identity age.Identity
		var err error

		switch {
		case strings.HasPrefix(line, "#") || line == "":
			continue
		case strings.HasPrefix(line, "AGE-PLUGIN-"):
			identity, err = plugin.NewIdentity(line, &plugin.ClientUI{})
		case strings.HasPrefix(line, "AGE-SECRET-KEY-1"):
			identity, err = age.ParseX25519Identity(line)
		}

		if err != nil || identity == nil {
			return nil, fmt.Errorf("failed to parse identity at line %d", lineNumber)
		}

		identities = append(identities, identity)
	}

	return identities, nil
}
