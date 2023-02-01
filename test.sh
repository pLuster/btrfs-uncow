#!/bin/bash

if [ -z "$DEST" ]; then
    DEST=/tmp/
fi

if [ -z "$PYTHON" ]; then
    PYTHON=python3
fi

if [ -z "$TSIZE" ]; then
    TSIZE=1024*1024*3
fi

if [ -z "$BSIZE" ]; then
    BSIZE=1024*1024
fi

if [ -z "$CSIZE" ]; then
    CSIZE=32*1024
fi

if ! stat -f "$DEST" | grep -q "Type: btrfs"; then
    echo "ERROR: set \$DEST to a btrfs test path"
    exit 100
fi

runtest() {

    # check a file block aligned
    fn="test-file"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes('$TSIZE'))
    '
    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"

    # check a file not block aligned
    fn="test-file-not-block-aligned"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes('$TSIZE' + 100))
    '
    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"


    # check a file ending with an hole
    fn="test-filewith-hole-end"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes('$TSIZE'))
    '
    truncate -s $(( $TSIZE + $CSIZE*3 )) "$DEST/btrfs-uncow-$fn"
    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"


    # check a file with an hole in the middle
    fn="test-filewith-hole-in-the-middle"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes('$TSIZE'))
    '

    truncate -s $(( $TSIZE + $BSIZE*3 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$TSIZE'))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"

    # check a file with an hole in the middle of the copy block
    fn="test-file-with-hole-in-the-first-copy-block"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes(int('$CSIZE' / 4)))
    '

    truncate -s $(( $CSIZE / 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$CSIZE'))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"


    # check a file with two hole in the middle of the copy-block
    fn="test-file-with-2-hole-in-the-first-copy-block"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes(int('$CSIZE' / 4)))
    '

    truncate -s $(( $CSIZE / 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$CSIZE'))
    '
    truncate -s $(( $CSIZE * 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$CSIZE' * 8))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"

    # check a file with an hole between two blocks size
    fn="test-file-with-hole-between-2-blocks-size"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes(int('$BSIZE' / 4)))
    '

    truncate -s $(( $BSIZE * 3 / 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$BSIZE'))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"

    # check a file ending with an hole between two copy blocks
    fn="test-file-with-hole-between-2-copy-blocks"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "wb").write(random.randbytes(int('$CSIZE' / 4)))
    '

    truncate -s $(( $CSIZE * 3 / 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$CSIZE'))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"

    # check a file beginning with an hole 
    fn="test-file-beginning-with-hole"
    truncate -s $(( $CSIZE * 3 / 2 )) "$DEST/btrfs-uncow-$fn"
    $PYTHON -c '
import random
random.seed(2)
open("'$DEST'btrfs-uncow-'$fn'", "ab").write(random.randbytes('$CSIZE'))
    '

    test_btrfs_uncow "$DEST/btrfs-uncow-$fn"


}

test_btrfs_uncow() {
    src="$1"
    dst="$1.new"
    rm -f "$dst"
    md1="$(md5sum "$src" | awk '{ print $1 }')"
    ls1="$(ls -s "$src" |  awk '{ print $1 }')"
    ./btrfs-uncow "$src" "$dst" >/dev/null
    md2="$(md5sum "$dst" | awk '{ print $1 }')"
    ls2="$(ls -s "$dst" |  awk '{ print $1 }')"
    if [ "$md1" != "$md2" ]; then
        echo "FAILED md5 $src ($md1)-> $dst ($md2)"
    elif [ "$ls1" != "$ls2" ]; then
        echo "FAILED sz $src ($ls1)-> $dst ($ls2)"
    else
        echo "SUCCESS $src"
    fi
}


main() {
    make clean &>/dev/null
    make CFLAGS="-DDEBUGBLOCKSIZE=$BSIZE -DDEBUGCOPYSIZE=$CSIZE" || return
    runtest
    make clean &>/dev/null
}
main
