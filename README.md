# btrfs-uncow
Creating a No Copy-on-Write (NOCOW) copy while trying to be smart with truncate to save disk space during the process.

The uncow consumes the source file in the process, one gigabyte at a time, but no data is lost if interrupted. The uncow can be resumed at any time using the same destination file. File holes are preserved so the size on disk won't increase.

A sync of the source filesystem is performed as a final step to reclaim all freed space, which can take a while with heavily fragmented files on mechanical drives. Make it optional?
