# Sync-with-Remote

This simple Hy script syncs a local directory with a remote directory designated by the user. (Thus, it is a client program rather than a server program.) Use this script as follows:

## Usage

### Installing dependencies

- At local: `pip install hy paramiko scp`
- At remote: `apt-get install tree` or `brew install tree`, depending on OS

### Running the script

1. At the local machine, place the script at a directory you want to sync with the remote directory.
2. Run the script as `hy sync.hy`
3. Provide the followings as prompted:
    1. Remote address
    2. Remote username
    3. Remote port number (recall that ssh's port number defaults to 22)
    4. Remote password
    5. Target remote directory as absolute path

## Effect

This script does the following:

1. Creates subdirectories in local dir not present in remote dir
2. Creates subdirectories in remote dir not present in local dir
3. Uploads files in local dir not present in remote dir
4. Downloads files in remote dir not present in local dir

thus syncing the two directories.
