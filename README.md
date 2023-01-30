# btrfs-uncow
Creating a No CoW copy while trying to be smart with truncate to save disk space.
A huge drawback is that sparse files will grow.

The copy mechanism destroys the source during the copying but the process can be interrupted and continued.
