
BASE_DIR=`pwd`
BUILD_DIR="$BASE_DIR/build"
DIST_DIR="$BASE_DIR/dist"
FILES_DIR="$BASE_DIR/files"

# Create folders
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$FILES_DIR"

OPENSSL_NAME="openssl-$VERSION"
OPENSSL_FILE="$OPENSSL_NAME.tar.gz"
OPENSSL_URL="http://www.openssl.org/source/$OPENSSL_FILE"
OPENSSL_PATH="$FILES_DIR/$OPENSSL_FILE"
OPENSSL_CONFIG_OPTIONS="-no-asm"

## --------------------
## OpenSSL
## --------------------
function download_openssl() {
    if [ ! -e "$OPENSSL_PATH" ]; then
        #curl -L "$OPENSSL_URL" -o "$OPENSSL_PATH"
        log_title "Download ${OPENSSL_NAME}"
        wget --output-document=${OPENSSL_PATH} ${OPENSSL_URL} -q
    fi
}

## --------------------
## Functions
## --------------------

function log_title() {
    echo '################################################'
    echo "$1"
    echo '################################################'
}

function unarchive() {
    if [ -z $1 ]; then
        echo "Missing extracted directory name to move"
        exit 21
    elif [ -z $2 ]; then
        echo "Missing ZIP file to extract"
        exit 22
    elif [ -z $3 ]; then
        echo "Missing target name"
        exit 23
    elif [ -z $4 ]; then
        echo "Missing target directory"
        exit 24
    fi
    
    EXTRACTED_NAME=$1
    ZIP_PATH=$2
    TARGET=$3
    TARGET_DIR=$4
    
    if [ -d $TARGET_DIR ]; then
        echo "Remove unarchive target dir for $TARGET"
        rm -dr $TARGET_DIR
    fi
    
    echo "Unarchive sources for $TARGET..."
    (cd $BUILD_DIR; tar -zxf $ZIP_PATH; mv $EXTRACTED_NAME $TARGET_DIR;) || exit 29
}
