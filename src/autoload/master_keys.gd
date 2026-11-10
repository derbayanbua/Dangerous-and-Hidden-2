class_name MasterKeys
extends RefCounted
## Vertrauenswürdige öffentliche Schlüssel des Masterservers (0.11, Onlinemodus).
## Nur Public Keys (RSA-3072, PKIX-PEM). Der private Schlüssel liegt nie im Repo/Spiel.
## kid = "m1-" + erste 16 Hex-Zeichen von SHA-256(DER).

const TRUSTED := {
	"m1-c9f3acbc4337f2ef": {
		"sha256_der": "c9f3acbc4337f2ef3919db3f79101bfbd589526118d103843f63a1579f281ddc",
		"pem": """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAn4l1DLiB0kBuqwf2HqS1
n5IgFtvAbU7du6OzVeufQObAnnS+A+Gbm0pKnMKBb5NKGwGPlr7rrKbxH01PElBg
ARZlgWZzIf97HLqDSN+Xml5Z2pCZ6Kvp7Y+toB0K/cXSQmm3L1V6rfcI6aFx4QAr
ZJ03m/R9VXdsVf0cGeTk9bHUefMJHX4DXeKlGlwvgn3xeAS/wIzfafeVmDr0rLT9
V/+w+CrHpuNOPbbrYfD6eBP7ZTkL7TGna9tYGwo2nIfNb6zJ5Es+Omy/1dAgydhN
E+ZsnFoSPnkBNpWUl7OJ6SNolEYxqNuyIKOI7KqR+Mt5BqQnxMxiI0SX/fVoMwBM
oD7EAQD7uNNL7r6W3zLgDv7UHwLKh20uXLRO8bHIdRwpZ4yQKS3HCpghW6FeoiK6
6n1SAg5CAXF+S/ZpO/K6N913Pn01lfsa0NWjuYT32bhw5BBDH4rQsS7G8UBGBRm3
ZCHqCTbqOcfDlp+R1f0LIBRShwcBKhL+J/MiY3n0BMEVAgMBAAE=
-----END PUBLIC KEY-----
""",
	},
}


static func has_kid(kid: String) -> bool:
	return TRUSTED.has(kid)


## CryptoKey (nur öffentlich) zu einer kid, sonst null.
static func key_for(kid: String) -> CryptoKey:
	if not TRUSTED.has(kid):
		return null
	var k := CryptoKey.new()
	if k.load_from_string(String(TRUSTED[kid]["pem"]), true) != OK:
		return null
	return k


## Prüft eine RSA-SHA256-Signatur über `data` mit dem Schlüssel `kid`.
static func verify(kid: String, data: PackedByteArray, signature: PackedByteArray) -> bool:
	var k := key_for(kid)
	if k == null:
		return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(data)
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest.finish(), signature, k)
