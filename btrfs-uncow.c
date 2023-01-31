#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <errno.h>
#include <assert.h>

#ifdef DEBUGBLOCKSIZE
const size_t block_size = DEBUGBLOCKSIZE;
const size_t copy_size = DEBUGCOPYSIZE;
#else
const size_t block_size = 1024*1024*1024;
const size_t copy_size = 32*1024*1024;
#endif
void *copy_buffer;

void copy(int dst, int src, size_t len)
{
	while (len > 0) {
		ssize_t l = len < copy_size ? len : copy_size;
		ssize_t in = read(src, copy_buffer, l);
		//printf("in=%ld\n", in);
		if (in < 0) {
			perror("read src");
			exit(EXIT_FAILURE);
		} else if (in == 0) {
			// If in == 0 and len > 0 we are not reading
			// all the data. This is dangerous and unexpected.
			// We cannot tolarate, because the ftruncate()
			// called in main assumes that all data is copied
			assert(0);
		}

		ssize_t i = 0;
		while (in) {
			ssize_t	out = write(dst, copy_buffer + i, in);
			if (out < 0) {
				perror("write dst");
				exit(EXIT_FAILURE);
			}
			len -= out;
			i += out;
			in -= out;
		}
	}
	return;
}

void copy2(int dst, int src, size_t len2)
{

	off_t cur_pos = lseek(src, 0, SEEK_CUR);
	if (cur_pos < 0) {
		perror("lseek SEEK_CUR");
		exit(EXIT_FAILURE);
	}

	off_t hole_pos = -1;
	while (len2 > 0) {
		size_t len;

		// Looking for an hole is an expensive operation. Do it only if needed.
		if (hole_pos < 0) {
			hole_pos = lseek(src, cur_pos, SEEK_HOLE);
			if (hole_pos < 0) {
				perror("lseek SEEK_CUR");
				exit(EXIT_FAILURE);
			}
		}

		if (hole_pos == cur_pos) {
			// We are at the beginning of an hole, skip it
			//fprintf(stderr, "skip from=%ld; len2=%ld\n", cur_pos, len2);

			// NB: it is assumed that after "len2" bytes there is
			// only the end of src file; so we don't need to check
			// where data_pos ends.
			off_t data_pos = lseek(src, cur_pos, SEEK_DATA);
			if (data_pos < 0 && errno == ENXIO) {
				// No further data, end the copy.
				// dst was alredy extended so no further extension is needed.
				return;
			}
			if (data_pos < 0) {
				perror("lseek SEEK_DATA");
				exit(EXIT_FAILURE);
			}
			if (lseek(dst, data_pos, SEEK_SET) < 0)  {
				perror("lseek SEEK_SET");
				exit(EXIT_FAILURE);
			}
			len2 -= (data_pos - cur_pos);
			cur_pos = data_pos;

			// Continue the loop and search anothe hole
			hole_pos = -1;
			continue;
		} else  {
			// Copy the data up to the next hole ...
			len = hole_pos - cur_pos;

			// ... but only up to the current block size
			if (len > len2)
				len = len2;

			// Move back to cur_pos
			if (lseek(src, cur_pos, SEEK_SET) < 0) {
				perror("lseek SEEK_CUR");
				exit(EXIT_FAILURE);
			}
		}

		copy(dst, src, len);
		len2 -= len;
		cur_pos += len;
	}
	return;
}

mode_t get_mode(int fd)
{
	struct stat statbuf;

	if (fstat(fd, &statbuf) == -1) {
		perror("fstat");
		exit(EXIT_FAILURE);
	}
	return statbuf.st_mode;
}

int main(int argc, char *argv[])
{
	if (argc < 3) {
		fprintf(stderr, "%s <src> <dst>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	int src, dst;
	if ((src = open(argv[1], O_RDWR)) == -1) {
		fprintf(stderr, "Failed to open source '%s': ", argv[1]);
		perror(NULL);
		exit(EXIT_FAILURE);
	}

	if ((dst = open(argv[2], O_CREAT|O_RDWR, get_mode(src))) == -1) {
		fprintf(stderr, "Failed to open destination '%s': ", argv[2]);
		perror(NULL);
		exit(EXIT_FAILURE);
	}

	if ((copy_buffer = malloc(copy_size)) == NULL) {
		perror(NULL);
		exit(EXIT_FAILURE);
	}

	off_t pos;
	if ((pos = lseek(dst, 0, SEEK_END)) == -1) {
		perror(NULL);
		exit(EXIT_FAILURE);
	}

	if (pos == 0) {
		int attr = FS_NOCOW_FL;
		if (ioctl(dst, FS_IOC_SETFLAGS, &attr) == -1) {
			fprintf(stderr, "Failed to set NoCoW flag on '%s': ", argv[2]);
			perror(NULL);
			//exit(EXIT_FAILURE);
		}

		if (ftruncate(dst, lseek(src, 0, SEEK_END)) == -1) {
			perror("truncate dst");
			exit(EXIT_FAILURE);
		}
		printf("Created new file '%s'\n", argv[2]);
	}
	else {
		printf("Continuing with existing file '%s'\n", argv[2]);
	}

	if ((pos = lseek(src, 0, SEEK_END)) == -1) {
		perror(NULL);
		exit(EXIT_FAILURE);
	}

	while (pos > 0) {
		size_t l;
		if (block_size > pos) {
			l = pos;
			pos = 0;
		} else {
			pos = pos - block_size;
			l = block_size;
		}
		printf("Copying from position %ld...   \n", pos);

		if (lseek(src, pos, SEEK_SET) == -1) {
			perror("seek src");
			exit(EXIT_FAILURE);
		}
		if (lseek(dst, pos, SEEK_SET) == -1) {
			perror("seek dst");
			exit(EXIT_FAILURE);
		}

		copy2(dst, src, l);
		if (fdatasync(dst) == -1) {
			perror("datasync dst");
			exit(EXIT_FAILURE);
		}

		if (ftruncate(src, pos) == -1) {
			perror("truncate src");
			exit(EXIT_FAILURE);
		}
		if (fdatasync(src) == -1) {
			perror("datasync src");
			exit(EXIT_FAILURE);
		}
	}

	fsync(dst);
	close(dst);
	printf("Copying done! Syncing source fs which can take a while if the CoW:ed file was heavily fragmented...\n");
	syncfs(src);
	close(src);
	printf("Removing emptied '%s'.\n", argv[1]);
	remove(argv[1]);
	exit(EXIT_SUCCESS);
}
