class_name MarketSeed
extends RefCounted


const MODULUS := 2147483647
const SALT_STEP := 7919


static func mix(seed: int, key: String, salt: int) -> int:
	var value := absi(seed) + salt * SALT_STEP
	for i in range(key.length()):
		value = int((value * 31 + key.unicode_at(i)) % MODULUS)
	return value


static func unit(seed: int, key: String, salt: int) -> float:
	return float(mix(seed, key, salt) % 1000) / 1000.0
