btrfs-uncow: btrfs-uncow.c
	gcc $(CFLAGS) -g -Og -Wall -o btrfs-uncow btrfs-uncow.c

clean:
	rm -f btrfs-uncow
