extends SceneTree
## Masterserver-Public-Key: lädt, Fingerabdruck stimmt, fremde Signatur wird abgelehnt.

func _init() -> void:
	var ok := 0
	var fail := 0
	var kid := "m1-c9f3acbc4337f2ef"
	var k := MasterKeys.key_for(kid)
	if k != null and k.is_public_only(): ok += 1
	else: fail += 1; print("FAIL  Schlüssel lädt nicht als Public Key")
	var pem := String(MasterKeys.TRUSTED[kid]["pem"])
	var b64 := pem.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").strip_edges().replace("\n", "")
	var der := Marshalls.base64_to_raw(b64)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(der)
	if h.finish().hex_encode() == MasterKeys.TRUSTED[kid]["sha256_der"]: ok += 1
	else: fail += 1; print("FAIL  SHA-256 der DER passt nicht")
	if kid.substr(3) == String(MasterKeys.TRUSTED[kid]["sha256_der"]).substr(0, 16): ok += 1
	else: fail += 1; print("FAIL  kid passt nicht zum Fingerabdruck")
	var bad := PackedByteArray(); bad.resize(384)
	if not MasterKeys.verify(kid, "x".to_utf8_buffer(), bad): ok += 1
	else: fail += 1; print("FAIL  falsche Signatur akzeptiert")
	if not MasterKeys.verify("m1-unbekannt", "x".to_utf8_buffer(), bad): ok += 1
	else: fail += 1; print("FAIL  unbekannte kid akzeptiert")
	print("ERGEBNIS: %d bestanden, %d fehlgeschlagen" % [ok, fail])
	quit(0 if fail == 0 else 1)
