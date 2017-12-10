#!/bin/bash

rootDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $rootDir

CNF=/etc/ssl/openssl.cnf

CAKEY=/etc/ssl/private/cakey.pem
CACRT=/etc/ssl/cacert.pem
NEWCRT=/etc/ssl/newcerts
IDX=/etc/ssl/index.txt
IDXA=/etc/ssl/index.txt.attr
SERIAL=/etc/ssl/serial

if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit
fi

function setSubj() {
    SUBJ="/C=US/ST=Denial/L=Springfield/O=Dis/CN=$1"
}

echo "### remove old"
rm -fr *.crt
rm -fr *.csr
rm -fr *.key
echo ""

echo "### create ca"
    rm -fr $CAKEY $CACRT $NEWCRT $IDX $IDXA $SERIAL
    mkdir -p $NEWCRT
    touch $IDX
    touch $IDXA
    echo "00" > $SERIAL

    setSubj ca
    openssl req -config $CNF -newkey rsa:4096 -x509 -nodes -extensions v3_ca -subj $SUBJ -keyout $CAKEY -out $CACRT
echo ""

echo "### create self signed"
setSubj self
openssl req -newkey rsa:4096 -nodes -keyout self.key -out self.crt -subj $SUBJ
echo ""

echo "### create signed"
setSubj signed
openssl req -new -sha256 -newkey rsa:4096 -nodes -keyout signed.key -out signed.csr -subj $SUBJ &&
openssl ca -batch -config $CNF -in signed.csr -out signed.crt
echo ""

echo "### create invalid"
setSubj invalid
openssl req -new -sha256 -newkey rsa:4096 -nodes -keyout invalid.key -out invalid.csr -subj $SUBJ &&
# it has to last at least 1 day, so test will be successful tomorrow
openssl ca -batch -config $CNF -days 1 -in invalid.csr -out invalid.crt
echo ""

echo "### create revoked"
setSubj revoked
openssl req -new -sha256 -newkey rsa:4096 -nodes -keyout revoked.key -out revoked.csr -subj $SUBJ &&
openssl ca -batch -config $CNF -in revoked.csr -out revoked.crt &&
openssl ca -batch -config $CNF -revoke revoked.crt
echo ""
