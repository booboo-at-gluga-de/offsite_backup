# Encrypted and Bandwidth Optimized Offsite Backup

If you want to create an encrypted backup of your data on a physical different location and you want to produce as less traffic on your internet connection as possible, than this is a solution you definitively want to have a look at!

## Design Criteria

  * Good backups follow the 3-2-1 rule:
     ** You have at least 3 generations of backup
     ** on at least 2 different media.
     ** At any given point in time at least 1 of them is offline.
     ** At any given point in time at least 1 of them is kept in a physical different lacation.
  * No need to fully trust the storage provider.
    (All encryption is done locally on a device you trust. The storage provide sees encrypted data only.)
  * Filenames of your data are considered to be sensitive - they are to be encrypted too.
  * Internet bandwidth (for transferring backup data to the storage provider) is considered to be "of value".
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
