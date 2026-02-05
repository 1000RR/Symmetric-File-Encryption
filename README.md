FILE-ENCRYPTION
===============

Deterministic, scriptable file encryption with **post‑quantum–resilient key derivation**, implemented using standard Unix tooling.

This repository provides **two pairs of Zsh scripts**:

1. **Ledger‑based encryption/decryption**
   - Maintains a mapping between encrypted filenames and original filenames
2. **Ledger‑free encryption/decryption**
   - Explicit input/output paths only, no metadata file

Both variants share the **same cryptographic core** and **interoperate at the key level**.

---

POST‑QUANTUM CONTEXT (IMPORTANT)
--------------------------------

These scripts are **post‑quantum–resilient in their key derivation**, though not “pure PQ crypto” in the strict academic sense.

### What *is* post‑quantum here

- **Argon2id** is used as the primary KDF in secret+salt mode
  - Argon2id is considered **quantum‑resilient**:
    - Grover’s algorithm only provides a quadratic speedup
    - Memory hardness dominates attack cost
- Keys derived are **256‑bit**, maintaining ≥128‑bit post‑quantum security margins

### What is *not* post‑quantum

- **AES‑256‑CTR** (symmetric cipher)
- **HMAC‑SHA256**

These are *not* post‑quantum algorithms, but:
- Symmetric cryptography degrades gracefully under quantum attack
- AES‑256 retains ~128‑bit security against Grover
- HMAC‑SHA256 remains secure with doubled work factor

👉 **Bottom line:**  
This system is **post‑quantum–resilient for practical purposes**, especially for long‑term storage, but does **not** claim formal PQ‑encryption status like Kyber/Dilithium.

---

OPENSSL DEPENDENCY & LONG‑TERM VIABILITY
----------------------------------------

The scripts rely on **OpenSSL CLI** as present on the host system (developed and tested with OpenSSL 3.x).

Used primitives:
- AES‑256‑CTR
- HMAC‑SHA256
- SHA‑256

These primitives are:
- NIST‑standardized
- Core to TLS and modern cryptography
- Extremely unlikely to be removed from OpenSSL

### Do you need to vendor OpenSSL?

**No, in almost all cases.**

Recommended practices:

- Record the OpenSSL version used:
  ```bash
  openssl version
  ```
- Store this README alongside encrypted data

For extreme archival (10–20+ years):
- Archive a **statically linked OpenSSL binary per OS**
- Vendoring OpenSSL source and build chains is **not necessary** unless facing hostile future environments

---

CRYPTOGRAPHIC CONSTRUCTION
--------------------------

### Encryption
- Cipher: **AES‑256‑CTR**
- IV: 16 bytes (random per file)
- Authentication: **HMAC‑SHA256**
- Construction: **Encrypt‑then‑MAC**

MAC input:
```
HMAC( MAC_KEY, IV || CIPHERTEXT )
```

### Sidecar files
For ciphertext file `X`:
- `X.iv`   — IV (32 hex characters)
- `X.hmac` — HMAC‑SHA256 (64 hex characters)

Both are required for decryption.

---

KEY MODES (CRITICAL)
-------------------

### 1. Secret + Salt (Argon2 mode)

Two independent keys with domain separation:

```
ENC_KEY = SHA256( Argon2id(secret, salt | "enc") )
MAC_KEY = SHA256( Argon2id(secret, salt | "mac") )
```

Argon2 parameters:
- `-id`
- `-m 23`  (≈8 GiB RAM)
- `-t 3`
- `-p 1`
- `-r`

This mode is:
- Memory‑hard
- Password‑based
- Post‑quantum‑resilient

---

### 2. `-k` Mode (Pre‑derived keys)

No Argon2 is run.

Environment variable **must contain exactly**:
```
ENC_KEY_HEX|||MAC_KEY_HEX
```

- Each key: 64 hex chars (256‑bit)
- Produced by `derive-key.zsh`
- Enables deterministic, portable decryption without re‑running Argon2

---

FILES IN THIS REPOSITORY
-----------------------

### derive-key.zsh
Derives **both encryption and MAC keys** from `<secret> <salt>`.

Output format:
```
ENC_KEY_HEX|||MAC_KEY_HEX
```

Used to populate `-k` environment variables.

---

### Ledger‑based scripts

These maintain a **ledger file** mapping encrypted filenames to original filenames and timestamps.

#### encryptfile-with-ledger.zsh
- Encrypts a file
- Generates random encrypted filename
- Appends mapping to a ledger file

#### decryptfile-with-ledger.zsh
- Uses ledger to restore original filename
- Verifies HMAC before decryption
- Refuses overwrite

Use these when:
- You want opaque encrypted filenames
- You need filename recovery without manual tracking

---

### Ledger‑free scripts

These require **explicit input/output paths** and maintain **no metadata**.

#### encryptfile.zsh
- Encrypts input file
- Output path or directory explicitly provided
- Writes `.iv` and `.hmac` sidecars

#### decryptfile.zsh
- Decrypts `.enc` file
- Output path or directory explicitly provided
- Verifies integrity before decryption

Use these when:
- You want full manual control
- You do not want metadata files

---

DEPENDENCIES
------------

Required:
- zsh
- openssl
- xxd

Secret+salt mode additionally requires:
- argon2 CLI

Platforms tested:
- macOS
- Debian
- Raspberry Pi OS

---

SECURITY NOTES
--------------

- Secrets passed via argv may appear in process listings
- Prefer `-k` mode when traveling or scripting
- Protect environment variables carefully
- Sidecar files are integrity‑critical
- Scripts never overwrite existing output files

---

QUICK START
-----------

```bash
chmod +x derive-key.zsh encryptfile.zsh decryptfile.zsh

export MYKEY="$(./derive-key.zsh secret travel-v1)"

./encryptfile.zsh -k MYKEY notes.txt ./encrypted/
./decryptfile.zsh -k MYKEY ./encrypted/notes.txt.enc ./recovered/
```
