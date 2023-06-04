# Encrypted and Bandwidth Optimized Offsite Backup

If you want to create an encrypted backup of your data on a physical different location and you want to produce as less traffic on your internet connection as possible, than this is a solution you definitively want to have a look at!

## Design Criteria

  * Good backups follow the 3-2-1 rule:
     * You have at least **3 generations** of backup
     * on at least **2 different media**.
     * At any given point in time at least **1** of them is **offline**.
     * At any given point in time at least **1** of them is kept in a **physical different location**.
  * No need to fully trust the storage provider. \
    (All encryption is done locally on a device you trust. The storage provide sees encrypted data only.)
  * Filenames of your data are considered to be sensitive - they are to be encrypted too.
  * Internet bandwidth (for transferring backup data to the storage provider) is considered to be "of value". \
    (Backup size might be dozends or hundreds of GB in total, but upstream of a DSL connection is limited. Anyway you want the backup job to finish in reasonable time. Or maybe the volume of your internet traffic is limited by your contract.)
  * Even if the size of your data in total is huge, the amount of changed data between one backup and the next is way smaller.
    So you definitely want to transfer the changed data only (and do not want to transfer the complete backup again).
  * Use standard tools only (which are available for most Linux distributions).

## How it is Realized

  * rsync is the tool to synchronize data between locations. It by default works bandwidth optimized (transfers changed data only on subsequent calls).
  * gocryptfs is the tool to care for encryption of the data. It has a very rsync-friendly storage format and cares for encrypted filenames.
  * You need a local cache storage. A gocryptfs file system is created here.
  * The gocryptfs is mounted locally and your data is synchronized into the cleartext mountpoint by rsync.
  * The gocrpytfs is unmounted again - from this point in time you see encrypted data only in your local cache storage. This encrypted stuff is synchronized (again by rsync) to the (offsite) storage provider.
  * The offsite storage provider can be anything which is rsync compliant (rsync via ssh should be preferred, but not mandatory):
     * (Storage) offering of any web provider.
     * A Raspberry Pi or NAS located at a friend. \
       (This will probably need a port forwarding at the internet router plus a dynamic DNS name to make the storage reachable from your side.)
     * etc.

## How to Create a Backup

The script `offsite_backup.sh` provided here is meant as an example. You will need to edit it, to customize:
  * Which files/directories you want to include/exclude in your backup.
  * Where your local cache storage is located.
  * Which storage provider to use (including storage path over there, your credentials, etc.)

For information on all commandline parameters, call `offsite_backup.sh -h`

```
~# ./offsite_backup.sh -h

call using:

./offsite_backup.sh
    to start an offsite backup

./offsite_backup.sh -l
    update local copy only
    (do not sync it to remote)

./offsite_backup.sh -r
    sync local copy to the remote location only
    (but do not update the local copy)

./offsite_backup.sh -i
    to initialize the gocryptfs in /var/cache/offsite_backup/crypted

./offsite_backup.sh -m
    to mount the gocryptfs to /var/cache/offsite_backup/cleartext

./offsite_backup.sh -u
    to umount the gocryptfs

./offsite_backup.sh -R
    Restore:
    sync the encrypted copy from the remote server
    (storage-provider.example.com)
    back to the local directory
    /var/cache/offsite_backup/crypted
    Please note: The gocryptfs may not be mounted for restore.
    (will try umount if needed)
```


## Testing offsite_backup.sh

If you have [Vagrant](https://www.vagrantup.com/) installed and want to test `offsite_backup.sh` locally, it's easy to setup a storage provider:

```Bash
vagrant up
vagrant ssh-config > ssh-config.vagrant
```

Make sure you have a line like this in `~/.ssh/config` - right at the beginning

```Bash
Include ~/git/github/offsite_backup/ssh-config.vagrant
```

This makes sure you have:

  * A host which is reachable as `storage-provider.example.com`
  * A user `storageuser` there, with key authentication enabled
  * So if you try `ssh storageuser@storage-provider.example.com` you should be able to login immediately, without being prompted for a password
  * Directory `/opt/offsite_backup/` is created there for you and owned by `storageuser`
