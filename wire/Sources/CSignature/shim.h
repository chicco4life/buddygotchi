#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/sha.h>
#include <openssl/obj_mac.h>
static inline EC_KEY *boop_key(const unsigned char *pub, size_t n) {
    if (n != 65 || pub[0] != 4) return NULL;
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    const unsigned char *p = pub;
    if (!key || !o2i_ECPublicKey(&key, &p, n) || EC_KEY_check_key(key) != 1) { EC_KEY_free(key); return NULL; }
    return key;
}
static inline int boop_public(const unsigned char *pub, size_t n, unsigned char *digest) {
    EC_KEY *key = boop_key(pub, n); if (!key) return 0;
    SHA256(pub, n, digest); EC_KEY_free(key); return 1;
}
static inline int boop_verify(const unsigned char *pub, size_t n, const unsigned char *sig, size_t sn, const unsigned char *message, size_t mn) {
    EC_KEY *key = boop_key(pub, n); if (!key) return 0;
    unsigned char digest[32]; SHA256(message, mn, digest);
    int ok = ECDSA_verify(0, digest, 32, sig, (int)sn, key);
    EC_KEY_free(key); return ok == 1;
}
