# Base Image

All ai-dock images are extended from this base image.

This file should form the basis for the README.md for all extended images, with nothing but this introduction removed and additional features documented as required.

## Pre-built Images

Docker images are built automatically through a GitHub Actions workflow and hosted at the GitHub Container Registry. Browse [here](https://github.com/ai-dock/base-image/pkgs/container/base-image) for an image suitable for your target environment.

You can also self-build from source by editing `.env` and running `docker compose build`.

## Run Locally

A 'feature-complete' docker-compose.yaml file is included for your convenience. All features of the image are included - Simply edit the environment variables, save and then type `docker compose up`.

If you prefer to use the standard `docker run` syntax, the command to pass is `init.sh`.

## Run in the Cloud

This image should be compatible with any GPU cloud platform. You simply need to pass environment variables at runtime. Please raise an issue on this repository if your provider cannot run the image.

All images built for ai-dock are tested for compatibility with both [vast.ai](https://cloud.vast.ai/?ref=62897) and [runpod.io](https://runpod.io?ref=m0vk9g4f).

Images that include Jupyter are also tested to ensure compatibility with [Paperspace Gradient](https://console.paperspace.com/signup?R=FI2IEQI)

### Connecting to your instance

All services listen for connections at [`0.0.0.0`](https://en.m.wikipedia.org/wiki/0.0.0.0). This gives you some flexibility in how you interact with your instance:

_**Expose the ports**_

This is fine if you are working locally but can be **dangerous for remote connections** where data is passed in plaintext between your machine and the container over http.

_**SSH Tunnel**_

This is the preferred method. You will only need to expose port 22 (SSH) which can then be used with port forwarding to allow **secure** connections to your services.

If you are unfamiliar with port forwarding then you should read the guides [here](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys?refcode=405a7b000d31#setting-up-ssh-tunnels) and [here](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-tunneling-on-a-vps?refcode=405a7b000d31).

## Environment Variables

| Variable            | Description |
| ------------------- | ----------- |
| GPU_COUNT           | Limit the number of available GPUs |
| RCLONE_*            | Rclone configuration - See [rclone documentation](https://rclone.org/docs/#config-file) |
| SKIP_ACL            | Set `true` to skip modifying workspace ACL |
| SSH_PUBKEY          | Your public key for SSH |
| WORKSPACE           | A volume path. Defaults to `/workspace/` |

Environment variables can be specified by using any of the standard methods (`docker-compose.yaml`, `docker run -e...`). Additionally, environment variables can also be passed as parameters of `init.sh`.

Passing environment variables to `init.sh` is usually unnecessary, but may be useful in some cloud environments where the full `docker run` command cannot be specified.

Example usage: `docker run -e STANDARD_VAR1="this value" -e STANDARD_VAR2="that value" init.sh EXTRA_VAR="other value"`

## Software Management

A small software collection is installed by apt-get. This is mostly to provide basic functionality, but also includes `openssh-server` as the OS vendor is likely to be first to patch any security issues.

All other software is installed into its own environment by `micromamba`, which is a drop-in replacement for conda/mamba. Read more about it [here](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html).

Micromamba environments are particularly useful where several software packages are required but their dependencies conflict. 

### Installed Micromamba Environments

| Environment    | Packages / Rationale |
| -------------- | ----------------------------------------- |
| `base`         | micromamba's base environment |
| `system`       | `supervisord`, `rclone` - latest versions |

If you are extending this image or running an interactive session where additional software is required, you should almost certainly create a new environment first. See below for guidance.

### Useful Micromamba Commands

| Command                              | Function |
| -------------------------------------| --------------------- |
| `micromamba env list`                | List available environments |
| `micromamba activate [name]`         | Activate the named environment |
| `micromamba deactivate`              | Close the active environment |
| `micromamba run -n [name] [command]` | Run a command in the named environment without activating |

All ai-dock images create micromamba environments using the `--experimental` flag to enable hardlinks which can save disk space where multiple environments are available.

To create an additional micromamba environment, eg for python, you can use the following:

`micromamba --experimental create -y -c conda-forge -c defaults -n [name] python=3.10`

## Volumes

Data inside docker containers is ephemeral - You'll lose all of it when the container is destroyed.

You may opt to mount a data volume at `/workspace` - This is a directory that ai-dock images will look for to make downloaded data available outside of the container for persistence.

This is usually of importance where large files are downloaded at runtime.  Any image that makes use of this directory should replace this paragraph and document how and why /workspace is being utilised.

You can define an alternative path for the workspace directory by passing the environment variable `WORKSPACE=/my/alternative/path/` and mounting your volume there. This feature will generally assist where cloud providers enforce their own mountpoint location for persistent storage.

The provided docker-compose.yaml will mount the local directory `./workspace` at `/workspace`.

As docker containers generally run as the root user, new files created in /workspace will be owned by uid 0(root).

To ensure that the files remain accessible to the local user that owns the directory, the docker entrypoint will set a default ACL on the directory by executing the commamd `setfacl -d -m u:${WORKSPACE_UID}:rwx /workspace`.

If you do not want this, you can set the environment variable `SKIP_ACL=true`.

## Running Services

This image will spawn multiple processes upon starting a container because some of our remote environments do not support more than one container per instance.

All processes are managed by [supervisord](https://supervisord.readthedocs.io/en/latest/) and will restart upon failure until you either manually stop them or terminate the container.

*Some of the included services would not normally be found **inside** of a container. They are, however, necessary here as some cloud providers give no access to the host; Containers are deployed as if they were a virtual machine.*

### SSHD

A SSH server will be started if at least one valid public key is found inside the running container in the file `/root/.ssh/authorized_keys`

There are several ways to get your keys to the container.

- If using docker compose, you can paste your key in the local file `config/authorized_keys` before starting the container.
 
- You can pass the environment variable `SSH_PUBKEY` with your public key as the value.

- Cloud providers often have a built-in method to transfer your key into the container

If you choose not to provide a public key then the SSH server will not be started.

To make use of this service you should map port 22 to a port of your choice on the host operating system.

See [this guide](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys?refcode=405a7b000d31#) by DigitalOcean for an excellent introduction to working with SSH servers.

### Rclone mount

Rclone allows you to access your cloud storage from within the container by configuring one or more remotes. If you are unfamiliar with the project you can find out more at the [Rclone website](https://rclone.org/).

Any Rclone remotes that you have specified, either through mounting the config directory or via setting environment variables will be mounted at `/workspace/remote/[remote name]`. For this service to start, the following conditions must be met:

- Fuse3 installed in the host operating system
- Kernel module `fuse` loaded in the host
- Host `/etc/passwd` mounted in the container
- Host `/etc/group` mounted in the container
- Host device `/dev/fuse` made available to the container
- Container must run with cap-add SYS_ADMIN
- Container must run with securiry-opt apparmor:unconfined
- At least one remote must be configured

The provided docker-compose.yaml includes a working configuration (add your own remotes).

In the event that the conditions listed cannot be met, `rclone` will still be available to use via the CLI - only mounts will be unavailable.

If you intend to use the `rclone create` command to interactively generate remote configurations you should ensure port 53682 is accessible. See https://rclone.org/remote_setup/ for further details.

### Logtail

This script follows and prints the log files for each of the above services to stdout. This allows you to follow the progress of all running services through docker's own logging system.

If you are logged into the container you can follow the logs by running `logtail.sh`

## Open Ports

Some ports need to be open for the services to run or for certain features of the provided software to function

| Open Port           | Service / Description |
| ------------------- | --------------------- |
| 22                  | SSH server            |
| 53682               | Rclone interactive config |