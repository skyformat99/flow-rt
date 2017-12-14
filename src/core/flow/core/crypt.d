module flow.core.crypt;

private import deimos.openssl.ssl;
private import flow.core.util.error;
private import flow.core.util;

class CryptoInitException : FlowException {mixin exception;}

class CryptoException : FlowException {mixin exception;}

private RSA* load(T)(string key) if(is(T==RSA)) {
    import std.conv : to;

    if(key !is null) {
        BIO* bio = BIO_new_mem_buf(key.ptr.as!(void*), key.length.to!int);
        BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
        scope(exit) BIO_free(bio);

        return PEM_read_bio_RSAPrivateKey(bio, null, null, null);
    }

    return null;
}

private X509* load(T)(string crt) if(is(T==X509)) {
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

private struct GenCipher {
    ubyte[] key, iv, data;
}

private GenCipher loadCipher(ubyte[] data) {
    import flow.core.data.bin : unpack;

    GenCipher gen;
    gen.key = data.unpack;
    gen.iv = data.unpack;
    return gen;
}

/** cipher and hash decides what generator
will run for creating it it */
private GenCipher createCipher(string cipher, string hash) {
    switch(cipher~hash) {
        case SSL_TXT_AES128~SSL_TXT_SHA:
            return genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_aes_128_cbc", "EVP_sha")();
        case SSL_TXT_AES256~SSL_TXT_SHA:
            return genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_aes_256_cbc", "EVP_sha")();
        case SSL_TXT_AES_GCM~SSL_TXT_SHA:
            return genCipher!(SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA, "EVP_aes_192_gcm", "EVP_sha")();
        case SSL_TXT_AES128~SSL_TXT_SHA256:
            return genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA256, "EVP_aes_128_cbc", "EVP_sha256")();
        case SSL_TXT_AES256~SSL_TXT_SHA256:
            return genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA256, "EVP_aes_256_cbc", "EVP_sha256")();
        case SSL_TXT_AES_GCM~SSL_TXT_SHA256:
            return genCipher!(SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA256, "EVP_aes_192_gcm", "EVP_sha256")();
        default: assert(false);
    }
}

/// openssl cipher generator
private GenCipher genCipher(string title, string cipherFunc, string hashFunc)() {
    import deimos.openssl.rand : RAND_bytes;
    import flow.core.data.bin : pack;

    immutable ks = 256/8;
    immutable rounds = 3;

    auto pass = new ubyte[ks]; RAND_bytes(pass.ptr, ks);

    GenCipher ciph;
    ciph.key = new ubyte[ks];
    ciph.iv = new ubyte[ks];
    
    auto ret = EVP_BytesToKey(mixin(cipherFunc)(), mixin(hashFunc)(), null, pass.ptr, ks, rounds, ciph.key.ptr, ciph.iv.ptr);

    if(ret != ks)
        new CryptoException("couldn't generate "~title~" cipher");

    // they are packed together for communicating cipher
    ciph.data = ciph.key.pack~ciph.iv.pack;

    return ciph;
}

private EVP_CIPHER_CTX createCipherCtx(string hash, GenCipher ciph) {
    switch(hash) {
        case SSL_TXT_AES128:
            return genCipherCtx!(
                SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_128_cbc"
            )(ciph);
        case SSL_TXT_AES256:
            return genCipherCtx!(
                SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_256_cbc"
            )(ciph);
        case SSL_TXT_AES_GCM:
            return genCipherCtx!(
                SSL_TXT_AES_GCM~"+"~SSL_TXT_SHA, "EVP_DecryptInit_ex", "EVP_aes_192_gcm"
            )(ciph);
        default: assert(false);
    }
}

/// openssl cipher context generator
private EVP_CIPHER_CTX genCipherCtx(string title, string initFunc, string cipherFunc)(GenCipher ciph) {
    EVP_CIPHER_CTX ctx;
    
    EVP_CIPHER_CTX_init(&ctx);
    if(!mixin(initFunc)(&ctx, mixin(cipherFunc)(), null, ciph.key.ptr, ciph.iv.ptr))
        new CryptoException("couldn't initialize "~title~" encryption context");

    // double check
    if(!mixin(initFunc)(&ctx, null, null, null, null))
        new CryptoException("couldn't initialize "~title~" encryption context");

    return ctx;
}

/** it has to get locked so no thread can
kill others ctx by destructing it however
multiple readers can use it concurrently */
private class Cipher {
    private import core.thread;
    private import std.datetime.systime;

    private RwMutex lock;

    /// a cipher algorithm needs a hash algorithm
    private string cipher, hash;

    /// merged cipher data
    ubyte[] data() @property {return this.gen.data;}

    /// generated cipher
    private GenCipher _gen;

    // lazy load
    private GenCipher gen() @property {
        synchronized(this.lock.reader) {
            if(this._gen.data is null) {
                synchronized(this.lock)
                    this._gen = createCipher(cipher, hash);
            }
        }

        return this._gen;
    }

    private EVP_CIPHER_CTX[Thread] _ctx;

    /// lazy and per thread loading
    private EVP_CIPHER_CTX ctx() @property {
        /* even it does not crash openssl
        cannot use objects multithreaded
        since this is meant to run in reused threads
        every thread gets its own ctx */
        synchronized(this.lock.reader) if(Thread.getThis in this._ctx)
            return this._ctx[Thread.getThis];
        else {
            EVP_CIPHER_CTX ctx;
            synchronized(this.lock) {
                ctx = createCipherCtx(this.hash, this.gen);
                this._ctx[Thread.getThis] = ctx;
            }
            
            return ctx;
        }
    }

    this(string cipher, string hash) {
        this.lock = new RwMutex;

        this.cipher = cipher;
        this.hash = hash;
    }

    this(string cipher, string hash, ref ubyte[] data) {
        this._gen = GenCipher(data);

        this(cipher, hash);
    }

    void dispose() {
        synchronized(this.lock) {
            foreach(c; this._ctx.values)
                EVP_CIPHER_CTX_cleanup(&c);
        }

        this.lock.dispose;
        this.destroy;
    }

    ubyte[] encrypt(ref ubyte[] data) {
        import flow.core.util.log : Log, LL;
        import std.conv : to;

        synchronized(this.lock.reader) try {
            auto buf = new ubyte[data.length];            
            auto ds = data.length.to!int;
            EVP_CIPHER_CTX ctx = this.ctx;
            if(!EVP_EncryptUpdate(&ctx, buf.ptr, &ds, data.ptr, ds))
                throw new CryptoException("cipher error: encryption failed");
            return buf;
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }

    ubyte[] decrypt(ref ubyte[] crypt) {
        import flow.core.util.log : Log, LL;
        import std.conv : to;

        synchronized(this.lock.reader) try {
            auto data = new ubyte[crypt.length];
            auto ds = crypt.length.to!int;
            EVP_CIPHER_CTX ctx = this.ctx;
            if(!EVP_DecryptUpdate(&ctx, data.ptr, &ds, crypt.ptr, ds))
                throw new CryptoException("cipher error: encryption failed");
            return data;
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }
}

// @property bool valid() { return ; }

private struct RsaPubCtx {
    X509* crt;
    EVP_PKEY* pub;
    RSA* rsa;
    size_t bs; // block size of rsa key
}

private RsaPubCtx createRsaPubCtx(string crt) {
    auto ctx = RsaPubCtx();
    ctx.crt = crt.load!(X509);
    ctx.pub = X509_get_pubkey(ctx.crt);
    ctx.rsa = EVP_PKEY_get1_RSA(ctx.pub);
    ctx.bs = RSA_size(ctx.rsa);
    return ctx;
}

private void free(RsaPubCtx ctx) {
    RSA_free(ctx.rsa);
    EVP_PKEY_free(ctx.pub);
    X509_free(ctx.crt);  
}

private class Peer {
    private import core.thread;
    private import std.datetime.systime;

    private RwMutex lock;

    private Crypto crypto;

    private RsaPubCtx[Thread] _ctx;

    private string _crt;

    /// lazy and per thread loading
    private RsaPubCtx ctx() @property {
        /* as Cipher.ctx */
        synchronized(this.lock.reader) if(Thread.getThis in this._ctx)
            return this._ctx[Thread.getThis];
        else {
            auto ctx = RsaPubCtx();
            synchronized(this.lock) {
                try {
                    ctx = this._crt.createRsaPubCtx;
                } catch(Exception exc) {
                    throw new CryptoException("couldn't load peers certificate", null, [exc]);
                }

                if(ctx.crt is null || ctx.pub == null || ctx.rsa is null && ctx.bs > 0)
                    throw new CryptoException("couldn't load peers certificate");
                
                this._ctx[Thread.getThis] = ctx;
            }
            
            return ctx;
        }
    }

    private string cipher, hash;
    private Duration validity;

    /// ciphers used to encrypt outgoing packages
    private Cipher _outgoing;
    private ubyte[] outCrypt;
    private SysTime outValidity;

    private void createOutgoing() {
        import flow.core.data.bin : pack;

        Cipher ciph = new Cipher(this.cipher, this.hash);
        
        // encrypts and signs generated cipher
        auto data = ciph.data;
        auto crypt = this.encryptRsa(data);
        auto sig = this.crypto.sign(crypt);
        this.outCrypt = sig.pack~crypt.pack;
        this.outValidity = Clock.currTime + this.validity;
        this._outgoing = ciph;
    }

    private Cipher outgoing() @property {
        synchronized(this.lock.reader)  {
                if(this.outValidity < Clock.currTime) {
                    synchronized(this.lock) {
                        this._outgoing.dispose;
                        this.createOutgoing();
                    }
            }

            return this._outgoing;
        }
    }

    /// ciphers used to decrypt incoming packages
    private Cipher[ulong] incoming;
    private SysTime[ulong] inValidity;

    this(Crypto crypto, string crt, string cipher, string hash, Duration outValidity, bool check = true) {
        this.lock = new RwMutex;

        this.crypto = crypto;
        this._crt = crt;
        this.cipher = cipher;
        this.hash = hash;
        this.validity = outValidity;

        if(check) {
            /* TODO check certificate against authorities
            and destination against cn of certificate*/
        }

        this.createOutgoing();
    }

    void dispose() {
        synchronized(this.lock)
            foreach(ctx; this._ctx.values)
                ctx.free;

        this.lock.dispose;
        this.destroy;
    }

    bool check() {
        synchronized(this.lock.reader)
            return false; // TODO check with authority
    }

    /// verifies sig of data using peers certificate
    bool verify(ref ubyte[] data, ref ubyte[] sig) {
        synchronized(this.lock.reader)
            return true; // TODO
    }

    /// encrypts data via RSA for crt
    private ubyte[] encryptRsa(ref ubyte[] data) {
        import deimos.openssl.err : ERR_error_string, ERR_get_error;
        import std.conv : to;

        auto ds = data.length;

        ubyte[] crypt;
        synchronized(this.lock.reader) {
            auto buffer = new ubyte[this.ctx.bs];
            int ret;
            size_t i = 0;
            while(i < ds) {
                auto end = (i+this.ctx.bs)-RSA_PKCS1_PADDING_SIZE < ds ? (i+this.ctx.bs)-RSA_PKCS1_PADDING_SIZE : ds;

                auto len = (end-i).to!int;
                auto from = data[i..end];

                ret = RSA_public_encrypt(len, from.ptr, buffer.ptr, this.ctx.rsa, RSA_PKCS1_PADDING);
                if(ret == -1)
                    throw new CryptoException("rsa encryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

                i = end;
                crypt ~= buffer[0..ret];
            }

            return crypt;
        }
    }

    ubyte[] encrypt(ref ubyte[] data) {
        // binary rule: crypted cipher is packed, rest is data
        synchronized(this.lock.reader) { // TODO
            return this.outCrypt~this.outgoing.encrypt(data);
        }
    }

    /// wipes unused incoming ciphers
    private void cleanInCiphers() {
        foreach(h, c; this.incoming)
            if(this.inValidity[h] < Clock.currTime) {
                this.incoming.remove(h);
                c.dispose;
            }
    }

    /// unpacks received cipher data and creates its stuff if needed
    private Cipher addInCipher(ref ubyte[] cc) {
        import flow.core.data.bin : unpack, unbin;
        import std.conv : to;

        // get signature out of crypted cipher
        auto sig = cc.unpack;

        /* generate hash out of crypted data
        due to rsa encryption of randoms this should be representative */
        auto hash = sig[0..ulong.sizeof].unbin!long;

        synchronized(this.lock.reader) {        
            // if hash is known stay in reader mode and return cipher
            if(hash in this.incoming)
                return this.incoming[hash];
            // otherwise switch to writer mode and create
            else synchronized(this.lock) {
                // clean what is expired (requires writer mode)
                this.cleanInCiphers();

                // get crypted data out of crypted cipher
                auto crypt = cc.unpack;

                auto sigOk = sig !is null && this.verify(crypt, sig);
                auto data = this.crypto.decryptRsa(crypt);
                auto ciph = new Cipher(this.cipher, this.hash, data);
                this.inValidity[hash] = Clock.currTime + this.validity;
                
                this.incoming[hash] = ciph;

                return ciph;
            }
        }
    }

    /// decrypts encrypted data returning its plain bytes unless there is a key
    ubyte[] decrypt(ubyte[] crypt) { // parameter crypt will get modified (never ref)
        import flow.core.data.bin : unpack;
        import flow.core.util.log : Log, LL;
        try {
            // binary rule: crypted cipher is packed, rest is data
            auto cc = crypt.unpack;
            synchronized(this.lock.reader) {
                auto ciph = this.addInCipher(cc);
                
                if(ciph !is null)
                    return ciph.decrypt(crypt);
            }
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }
}

private struct RsaPrivCtx {
    RSA* rsa;
    size_t bs; // block size of rsa key
}

private RsaPrivCtx createRsaPrivCtx(string key) {
    auto ctx = RsaPrivCtx();
    ctx.rsa = key.load!(RSA);
    ctx.bs = RSA_size(ctx.rsa);
    return ctx;
}

private void free(RsaPrivCtx ctx) {
    RSA_free(ctx.rsa);
}

package final class Crypto {
    private import core.thread;
    private import core.time;

    private RwMutex lock;

    private string addr;
    private string key;
    private string crt;

    private RsaPrivCtx[Thread] _ctx;

    /// lazy and per thread loading
    private RsaPrivCtx ctx() @property {
        auto ctx = RsaPrivCtx();
        /* as Cipher.ctx */
        synchronized(this.lock.reader) if(Thread.getThis in this._ctx)
            return this._ctx[Thread.getThis];
        else {
            synchronized(this.lock) {
                try {
                    ctx = this.key.createRsaPrivCtx;
                } catch(Exception exc) {
                    throw new CryptoException("couldn't load own rsa key", null, [exc]);
                }

                if(ctx.rsa is null && ctx.bs > 0)
                    throw new CryptoException("couldn't load own rsa key");
                
                this._ctx[Thread.getThis] = ctx;
            }
            
            return ctx;
        }
    }

    // checking peers certivicate for CA validity?
    private bool _check;

    /// algorithms to use
    private string cipher, hash;

    /// validity time for outgoing cipher
    private Duration cipherValidity;

    /// available destinations
    private Peer[string] peers;

    shared static this() {
        import deimos.openssl.conf;

        // initializing ssl
        ERR_load_CRYPTO_strings();
        OpenSSL_add_all_algorithms();
        OPENSSL_config(null);
    }

    static dispose() {
        import deimos.openssl.err;

        EVP_cleanup();
        ERR_free_strings();
    }

    //https://www.youtube.com/watch?v=uwzWVG_LDGA

    this(string addr, string key, string crt, string cipher, string hash, bool check = true, Duration cipherValidity = 10.minutes) {
        this.lock = new RwMutex;

        this.addr = addr;
        this.key = key;
        this.crt = crt;
        
        /* aes-256 in combination with sha256 is
        the default cipher and hash pair to use */
        this.cipher = cipher != string.init ? cipher : SSL_TXT_AES_GCM;
        this.hash = hash != string.init ? hash : SSL_TXT_SHA;
        this._check = check;
        this.cipherValidity = cipherValidity;
    }

    void dispose() {
        synchronized(this.lock)
            foreach(ctx; this._ctx.values)
                ctx.free;
        
        this.lock.dispose;
        this.destroy;
    }

    /// add peer
    void add(string p, string crt) {
        synchronized(this.lock.reader)
            if(p !in this.peers)
                synchronized(this.lock)
                    this.peers[p] = new Peer(this, crt, this.cipher, this.hash, this.cipherValidity, this._check);
    }

    /// remove it again
    void remove(string p) {
        synchronized(this.lock.reader)
            if(p in this.peers)            
                synchronized(this.lock) {
                    auto peer = this.peers[p];
                    peer.dispose;
                    this.peers.remove(p);
                }
    }

    bool check(string dst) {
        synchronized(this.lock.reader)
            if(dst in this.peers)
                return this.peers[dst].check();
            else return false;
    }

    /** signs data using private key
    returns signature if there is a key else null */
    ubyte[] sign(ref ubyte[] data) {
        synchronized(this.lock.reader)
            return null; // TODO
    }

    bool verify(ref ubyte[] data, ref ubyte[] sig, string dst) {
        synchronized(this.lock.reader)
            if(dst in this.peers)
                return this.peers[dst].verify(data, sig);
            else return false;
    }

    ubyte[] encryptRsa(ref ubyte[] data, string dst) {
        synchronized(this.lock.reader)
            if(dst in this.peers)
                return this.peers[dst].encryptRsa(data);
            else return null;
    }

    ubyte[] decryptRsa(ref ubyte[] crypt) {
        import deimos.openssl.err : ERR_error_string, ERR_get_error;
        import std.conv : to;

        synchronized(this.lock.reader) {
            auto ds = crypt.length;

            ubyte[] data;
            auto buffer = new ubyte[this.ctx.bs-RSA_PKCS1_PADDING_SIZE];
            int ret;
            size_t i = 0;
            while(i < ds) {
                auto end = i+this.ctx.bs < ds ? i+this.ctx.bs : ds;

                auto len = (end-i).to!int;
                auto from = crypt[i..end];
                
                ret = RSA_private_decrypt(len, from.ptr, buffer.ptr, this.ctx.rsa, RSA_PKCS1_PADDING);
                if(ret == -1)
                    throw new CryptoException("rsa decryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

                i = end;
                data ~= buffer[0..ret]; // trim data to real size
            }

            return data;
        }
    }

    ubyte[] encrypt(ref ubyte[] data, string dst) {
        synchronized(this.lock.reader)
            return this.peers[dst].encrypt(data);
    }

    ubyte[] decrypt(ref ubyte[] crypt, string src) {
        synchronized(this.lock.reader)
            return this.peers[src].decrypt(crypt);
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

unittest { test.header("TEST core.crypt: rsa encrypt/decrypt, sign/verify");
    import deimos.openssl.ssl;
    import flow.core.data : bin, unbin;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    auto selfC = new Crypto("self", TestKeys.selfKey, TestKeys.selfCrt, SSL_TXT_AES_GCM, SSL_TXT_SHA, false);
    selfC.add("signed", TestKeys.signedCrt);

    auto signedC = new Crypto("signed", TestKeys.signedKey, TestKeys.signedCrt, SSL_TXT_AES_GCM, SSL_TXT_SHA, false);
    signedC.add("self", TestKeys.selfCrt);

    auto orig = "CRYPTED MESSAGE: hello world, I'm coming".bin;
    
    auto signedCrypt = signedC.encryptRsa(orig, "self");
    auto selfDecrypt = selfC.decryptRsa(signedCrypt);
    assert(orig == selfDecrypt, "original message and decrypt of self crypto mismatch");
    
    auto selfCrypt = selfC.encryptRsa(orig, "signed");
    auto signedDecrypt = signedC.decryptRsa(selfCrypt);
    assert(orig == signedDecrypt, "original message and decrypt of signed crypto mismatch");

    selfC.remove("signed");
    signedC.remove("self");

    selfC.dispose;
    signedC.dispose;
test.footer; }

/*version(unittest) {
    void runCipherTest(string cipher, string hash) {
        import flow.core.data : bin, unbin;

        auto selfC = new Crypto("self", TestKeys.selfKey, TestKeys.selfCrt, cipher, hash);
        auto signedC = new Crypto("signed", TestKeys.signedKey, TestKeys.signedCrt, cipher, hash);

        auto orig = "CRYPTED MESSAGE: hello world, I'm coming".bin;
        
        auto signedCrypt = signedC.encrypt(orig, "self", TestKeys.selfCrt);
        auto selfDecrypt = selfC.decrypt(signedCrypt);
        assert(orig == selfDecrypt, "original message and decrypt of self crypto mismatch");
        
        auto selfCrypt = selfC.encrypt(orig, "signed", TestKeys.signedCrt);
        auto signedDecrypt = signedC.decrypt(selfCrypt, "self", TestKeys.signedCrt);
        assert(orig == signedDecrypt, "original message and decrypt of signed crypto mismatch");
    }
}

unittest { test.header("TEST core.crypt: cipher encrypt/decrypt");
    import deimos.openssl.ssl;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    runCipherTest(SSL_TXT_AES128, SSL_TXT_SHA);
    runCipherTest(SSL_TXT_AES256, SSL_TXT_SHA);
    runCipherTest(SSL_TXT_AES_GCM, SSL_TXT_SHA);
    runCipherTest(SSL_TXT_AES128, SSL_TXT_SHA256);
    runCipherTest(SSL_TXT_AES256, SSL_TXT_SHA256);
    runCipherTest(SSL_TXT_AES_GCM, SSL_TXT_SHA256);
test.footer; }*/

//unittest { test.header("TEST core.crypt: self signed certificates check behavior"); test.footer(); }
//unittest { test.header("TEST core.crypt: signed certificates check behavior"); test.footer(); }
//unittest { test.header("TEST core.crypt: invalid certificates check behavior"); test.footer(); }
//unittest { test.header("TEST core.crypt: revoked certificates check behavior"); test.footer(); }