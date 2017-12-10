module flow.core.crypt;

private import flow.util;

package struct Cipher {
    import deimos.openssl.evp;
    import std.datetime.systime : SysTime;

    ubyte[] plain;
    ubyte[] crypt;

    SysTime until;
    
    EVP_CIPHER_CTX ctx;
}

package final class Crypto {
    import core.time : Duration, minutes;
    import deimos.openssl.conf;
    import deimos.openssl.evp;
    import deimos.openssl.rsa;
    import deimos.openssl.x509;

    RSA* _key;
    X509* _crt;

    string crt;
    string key;

    string cipher, hash;
    Duration cipherValidity;

    Cipher[string] outCiphers;
    Cipher[long][string] inCiphers;

    shared static this() {
        // initializing ssl
        ERR_load_CRYPTO_strings();
        OpenSSL_add_all_algorithms();
        OPENSSL_config(null);
    }

    /* shared static ~this {
        EVP_cleanup();
        ERR_free_strings();
    }*/

    //https://www.youtube.com/watch?v=uwzWVG_LDGA

    this(string key, string crt, string cipher, string hash, Duration cipherValidity = 10.minutes) {
        import deimos.openssl.ssl : SSL_TXT_AES_GCM, SSL_TXT_SHA256;
        import flow.core.error : CryptoInitException;

        this.key = key;
        this.crt = crt;
        
        /* aes-256 in combination with sha256 is
        the default cipher and hash pair to use */
        this.cipher = cipher != string.init ? cipher : SSL_TXT_AES_GCM;
        this.hash = hash != string.init ? hash : SSL_TXT_SHA256;
        this.cipherValidity = cipherValidity;

        this._key = this.loadKey(key);
        this._crt = this.loadCrt(crt);
    }

    RSA* loadKey(string key) {
        import deimos.openssl.pem;
        import flow.util : as;
        import std.conv : to;

        if(key !is null) {
            BIO* bio = BIO_new_mem_buf(key.ptr.as!(void*), key.length.to!int);
            BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
            scope(exit) BIO_free(bio);

            return PEM_read_bio_RSAPrivateKey(bio, null, null, null);
        }

        return null;
    }

    X509* loadCrt(string crt) {
        import deimos.openssl.pem;
        import flow.util : as;
        import std.conv : to;

        // for security reasons certificate first
        if(crt !is null) {
            BIO* bio = BIO_new_mem_buf(crt.ptr.as!(void*), crt.length.to!int);
            BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
            scope(exit) BIO_free(bio);

            return PEM_read_bio_X509(bio, null, null, null);
        }

        return null;
    }

    void cleanInCiphers(string src) {
        import deimos.openssl.evp;
        import std.datetime.systime;
        foreach(h; this.inCiphers[src].keys) {
            if(this.inCiphers[src][h].until < Clock.currTime) {
                EVP_CIPHER_CTX_cleanup(&this.inCiphers[src][h].ctx);

                this.inCiphers[src].remove(h);
            }
        }
    }

    void createCipherCtx(Cipher ciph, ubyte[] key, ubyte[] iv) {
        import deimos.openssl.ssl;

        // this guys should decrypt
        switch(this.cipher~this.hash) {
            case SSL_TXT_AES128:
                this.genCipherCtx!(SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_128_cbc")(ciph, key, iv);
                break;
            case SSL_TXT_AES256:
                this.genCipherCtx!(SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_256_cbc")(ciph, key, iv);
                break;
            case SSL_TXT_AES_GCM:
                this.genCipherCtx!(SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_192_gcm")(ciph, key, iv);
                break;
            default: break;
        }
    }
    
    /// gets cipher from received cipher data
    Cipher takeCipher(ref ubyte[] cc, string src, string crt) {
        import flow.core.error : CryptoException;
        import flow.data : unbin, unpack;
        import std.array : array;
        import std.conv : to;

        auto sig = cc.unpack;
        auto hby = sig[0..long.sizeof];
        auto hash = hby.unbin!long;

        this.cleanInCiphers(src);

        // if this one is't in, add the new        
        if(hash !in this.inCiphers[src]) {
            auto crypt = cc.unpack;
            auto sigOk = sig !is null && this.verify(crypt, sig, crt);

            auto ciph = Cipher();
            ciph.crypt = cc;
            ciph.plain = this.decryptRsa(cc);

            auto tmp = cc.dup;
            this.createCipherCtx(ciph, tmp.unpack, tmp.unpack);

            this.inCiphers[src][hash] = ciph;
            return ciph;
        } else 
            return this.inCiphers[src][hash];
    }

    Cipher createCipher() {
        import deimos.openssl.ssl;

        // chooses the right cipher generator function
        Cipher ciph;
        switch(this.cipher~this.hash) {
            case SSL_TXT_AES128~SSL_TXT_SHA:
                ciph = this.genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_aes_128_cbc", "EVP_sha")();
                break;
            case SSL_TXT_AES256~SSL_TXT_SHA:
                ciph = this.genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_aes_256_cbc", "EVP_sha")();
                break;
            case SSL_TXT_AES_GCM~SSL_TXT_SHA:
                ciph = this.genCipher!(SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA, "EVP_aes_192_gcm", "EVP_sha")();
                break;
            case SSL_TXT_AES128~SSL_TXT_SHA256:
                ciph = this.genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA256, "EVP_aes_128_cbc", "EVP_sha256")();
                break;
            case SSL_TXT_AES256~SSL_TXT_SHA256:
                ciph = this.genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA256, "EVP_aes_256_cbc", "EVP_sha256")();
                break;
            case SSL_TXT_AES_GCM~SSL_TXT_SHA256:
                ciph = this.genCipher!(SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA256, "EVP_aes_192_gcm", "EVP_sha256")();
                break;
            default: break;
        }

        return ciph;
    }

    /// generates cipher for receiver
    Cipher genCipher(string crt) {
        import deimos.openssl.ssl;
        import flow.data : pack;
        import std.datetime.systime;

        auto ciph = this.createCipher();
        
        // encrypts and signs generated key
        auto crypt = this.encryptRsa(ciph.plain, crt);
        auto sig = this.sign(crypt);
        ciph.crypt = sig.pack~crypt.pack;

        // set ciphers lifetime
        ciph.until = Clock.currTime + this.cipherValidity;

        return ciph;
    }

    Cipher genCipher(string title, string cipherFunc, string hashFunc)() {
        import flow.core.error : CryptoException;
        import deimos.openssl.rand;
        import flow.data : pack;

        immutable ks = 256/8;
        immutable rounds = 3;

        auto pass = new ubyte[ks]; RAND_bytes(pass.ptr, ks);
        auto key = new ubyte[ks];
        auto iv = new ubyte[ks];
        
        auto ret = EVP_BytesToKey(mixin(cipherFunc)(), mixin(hashFunc)(), null, pass.ptr, ks, rounds, key.ptr, iv.ptr);

        if(ret != ks)
            new CryptoException("couldn't generate "~title~" cipher");

        auto ciph = Cipher();
        ciph.plain = key.pack~iv.pack;

        // this one should encrypt
        this.genCipherCtx!(title, "EVP_EncryptInit_ex",  cipherFunc)(ciph, key, iv);

        return ciph;
    }

    void genCipherCtx(string title, string initFunc, string cipherFunc)(Cipher ciph, ref ubyte[] key, ref ubyte[] iv) {
        import flow.core.error : CryptoException;

        EVP_CIPHER_CTX_init(&ciph.ctx);
        if(!mixin(initFunc)(&ciph.ctx, mixin(cipherFunc)(), null, key.ptr, iv.ptr))
            new CryptoException("couldn't initialize "~title~" encryption context");

        // double check
        if(!mixin(initFunc)(&ciph.ctx, null, null, null, null))
            new CryptoException("couldn't initialize "~title~" encryption context");
    }

    /** check certificate against authorities
    and destination against cn of certificate*/
    bool check(string crt, string dst) {return false;}

    /** signs data using private key
    returns signature if there is a key else null */
    ubyte[] sign(ref ubyte[] data) {return null;}

    /** verifies sig of data using given certificate
    returns contained data or null */
    bool verify(ref ubyte[] data, ref ubyte[] sig, string crt) {return false;}

    /// encrypts data via RSA for crt
    ubyte[] encryptRsa(ref ubyte[] data, string crt) {
        import deimos.openssl.err;
        import flow.core.error : CryptoException;
        import std.conv : to;

        X509* oCrt = this.loadCrt(crt);
        if(oCrt !is null) {
            scope(exit) X509_free(oCrt);
            EVP_PKEY* pub = X509_get_pubkey(oCrt);
            scope(exit) EVP_PKEY_free(pub);
            RSA* key = EVP_PKEY_get1_RSA(pub);
            scope(exit) RSA_free(key);

            auto bs = RSA_size(key);
            auto ds = data.length;

            ubyte[] crypt;
            auto buffer = new ubyte[bs];
            int ret;
            size_t i = 0;
            while(i < ds) {
                auto end = (i+bs)-RSA_PKCS1_PADDING_SIZE < ds ? (i+bs)-RSA_PKCS1_PADDING_SIZE : ds;

                auto len = (end-i).to!int;
                auto from = data[i..end];

                ret = RSA_public_encrypt(len, from.ptr, buffer.ptr, key, RSA_PKCS1_PADDING);
                if(ret == -1)
                    throw new CryptoException("rsa encryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

                i = end;
                crypt ~= buffer[0..ret];
            }

            return crypt;
        } else throw new CryptoException("couldn't load receivers certificate");
    }

    ubyte[] decryptRsa(ref ubyte[] crypt) {
        import deimos.openssl.err;
        import flow.core.error : CryptoException;
        import std.conv : to;

        if(this._key !is null) {
            auto bs = RSA_size(this._key);
            auto ds = crypt.length;

            ubyte[] data;
            auto buffer = new ubyte[bs-RSA_PKCS1_PADDING_SIZE];
            int ret;
            size_t i = 0;
            while(i < ds) {
                auto end = i+bs < ds ? i+bs : ds;

                auto len = (end-i).to!int;
                auto from = crypt[i..end];
                
                ret = RSA_private_decrypt(len, from.ptr, buffer.ptr, this._key, RSA_PKCS1_PADDING);
                if(ret == -1)
                    throw new CryptoException("rsa decryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

                i = end;
                data ~= buffer[0..ret]; // trim data to real size
            }

            return data;
        } else throw new CryptoException("couldn't load own private key");
    }

    /* checks if destinations cipher is still vaild and if not replaces it
    if there is a new cipher, msgPrefix is filled with it otherwise marked empty*/
    Cipher getActualCipher(string dst, ref ubyte[] msgPrefix) {
        import flow.data : bin, pack;
        import std.datetime.systime : Clock;

        Cipher ciph;
        // if there is no cipher for that destination create one
        if(dst !in this.outCiphers || this.outCiphers[dst].until < Clock.currTime) {
            ciph = this.genCipher(crt);
            this.outCiphers[dst] = ciph;

            // mark there is a new cipher and append it's length and crypt
            msgPrefix ~= ciph.crypt.pack;
        } else {
            ciph = this.outCiphers[dst];

            /* for now it is intended to send it as prefix
            to each message until certain logical problems are solved */
            //msgPrefix ~= ubyte.min;
            msgPrefix ~= ciph.crypt.pack;
        }

        return ciph;
    }

    /** encrypting by symmetric cipher for certificate
    whichs key is encrypted using public key
    returns [encrypted symkey]~[encrypted data]*/
    ubyte[] encrypt(ref ubyte[] data, string crt, string dst) {
        import flow.core.error : CryptoException;
        import flow.data : pack;
        import flow.util;
        import std.conv : to;

        try {
            ubyte[] crypt;
            // write the encrypted cipher into buffer
            auto ciph = this.getActualCipher(dst, crypt);

            auto buf = new ubyte[data.length];            
            auto ds = data.length.to!int;
            if(!EVP_EncryptUpdate(&ciph.ctx, buf.ptr, &ds, data.ptr, ds))
                throw new CryptoException("cipher error: encryption failed");
            crypt ~= buf.pack;

            return crypt;
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }

    /// decrypts encrypted data returning its plain bytes unless there is a key
    ubyte[] decrypt(ref ubyte[] crypt, string src, string crt) {
        import flow.core.error : CryptoException;
        import flow.data : unpack;
        import flow.util;
        import std.conv : to;

        try {
            auto cc = crypt.unpack;
            auto ciph = this.takeCipher(cc, src, crt);

            auto data = new ubyte[crypt.length];
            auto ds = crypt.length.to!int;
            if(!EVP_DecryptUpdate(&ciph.ctx, data.ptr, &ds, crypt.ptr, ds))
                throw new CryptoException("cipher error: encryption failed");
            return data;
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }
}

version(unittest) {
    class TestKeys {
        shared static string selfKey, selfCrt;
        shared static string signedKey, signedCrt;
        shared static string invalidKey, invalidCrt;
        shared static string revokedKey, revokedCrt;

        shared static this() {
            import std.file : readText, thisExePath;
            import std.path : buildPath, dirName;

            string base = thisExePath.dirName.buildPath("..", "util", "ssl");

            selfKey = base.buildPath("self.key").readText;
            selfCrt = base.buildPath("self.crt").readText;
            
            signedKey = base.buildPath("signed.key").readText;
            signedCrt = base.buildPath("signed.crt").readText;

            invalidKey = base.buildPath("invalid.key").readText;
            invalidCrt = base.buildPath("invalid.crt").readText;

            revokedKey = base.buildPath("revoked.key").readText;
            revokedCrt = base.buildPath("revoked.crt").readText;
        }

        @property static bool loaded() {
            return selfKey != string.init
                && selfCrt != string.init
                && signedKey != string.init
                && signedCrt != string.init
                && invalidKey != string.init
                && invalidCrt != string.init
                && revokedKey != string.init
                && revokedCrt != string.init;
        }
    }
}

unittest { test.header("TEST engine.core: rsa encrypt/decrypt, sign/verify");
    import deimos.openssl.ssl;
    import flow.data : bin, unbin;
    import std.conv;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    auto selfC = new Crypto(TestKeys.selfKey, TestKeys.selfCrt, SSL_TXT_AES256, SSL_TXT_SHA256);
    auto signedC = new Crypto(TestKeys.signedKey, TestKeys.signedCrt, SSL_TXT_AES256, SSL_TXT_SHA256);

    auto orig = "CRYPTED MESSAGE: hello world, I'm coming".bin;
    
    auto signedCrypt = signedC.encryptRsa(orig, TestKeys.selfCrt);
    auto selfDecrypt = selfC.decryptRsa(signedCrypt);
    assert(orig == selfDecrypt, "original message and decrypt of self crypto mismatch");
    
    auto selfCrypt = selfC.encryptRsa(orig, TestKeys.signedCrt);
    auto signedDecrypt = signedC.decryptRsa(selfCrypt);
    assert(orig == signedDecrypt, "original message and decrypt of signed crypto mismatch");
test.footer; }

//unittest { test.header("TEST engine.core: self signed certificates check behavior"); test.footer(); }
//unittest { test.header("TEST engine.core: signed certificates check behavior"); test.footer(); }
//unittest { test.header("TEST engine.core: invalid certificates check behavior"); test.footer(); }
//unittest { test.header("TEST engine.core: revoked certificates check behavior"); test.footer(); }