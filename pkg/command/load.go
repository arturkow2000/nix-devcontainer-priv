package command

import (
	"fmt"

	"github.com/arturkow2000/nix-devcontainer/pkg/nix2docker"
	"github.com/containerd/containerd/v2/client"
	"github.com/containerd/containerd/v2/pkg/namespaces"
	cli "github.com/urfave/cli/v2"
)

var loadCommand = &cli.Command{
	Name:  "load",
	Usage: "loads an OCI archive into docker",
	Flags: []cli.Flag{},
	Action: func(c *cli.Context) error {
		if c.NArg() != 1 {
			return fmt.Errorf("must provide exactly 1 args")
		}

		client, err := client.New(c.String("address"))
		if err != nil {
			return err
		}

		archivePath := c.Args().Get(0)

		ctx := namespaces.WithNamespace(c.Context, "moby")
		_, err = nix2docker.Load(ctx, client, archivePath)
		return err
	},
}
