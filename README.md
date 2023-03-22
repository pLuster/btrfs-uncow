# btrfs-uncow
Creating a No Copy-on-Write (NOCOW) copy while trying to be smart with truncate to save disk space during the process. It uses 1GB disk space during the operation and you need some extra free disk space for a healthy filesystem as usual.

The uncow consumes the source file in the process, one gigabyte at a time, but no data is lost if interrupted. The uncow can be resumed at any time using the same destination file. File holes are preserved so the size on disk won't increase.

A sync of the source filesystem is performed as a final step to reclaim all freed space, which can take a while with heavily fragmented files on mechanical drives. Can be turned off with --no-syncfs.

An interrupted copy can also be combined by dd:ing the source over the destination; dd if=<source> of=<dest> conv=sparse,nocreat,notrunc,fsync
Resume is as simple and robust like that. No point in switching to dd though.

btrfs-uncow should work on all Copy-on-Write filesystems. Nothing is actually Btrfs specific.
