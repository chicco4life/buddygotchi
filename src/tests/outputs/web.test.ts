import { describe, expect, test } from "bun:test";
import { PairingManager } from "../../src/outputs/web";
import { join } from "path";
import { mkdtempSync } from "fs";
import { tmpdir } from "os";

function makePairing(ttlS = 86400): PairingManager {
  const dir = mkdtempSync(join(tmpdir(), "buddy-test-"));
  return new PairingManager(join(dir, "pairing.json"), ttlS);
}

describe("PairingManager", () => {
  test("rotateCode generates 6-char code", () => {
    const pm = makePairing();
    const code = pm.rotateCode();
    expect(code.length).toBe(6);
    expect(/^[A-Z2-9]+$/.test(code)).toBe(true);
  });

  test("authorize with valid code issues token", () => {
    const pm = makePairing();
    const code = pm.rotateCode();

    const result = pm.authorize("client1", code);
    expect(result.ok).toBe(true);
    expect(result.issuedToken).toBeDefined();
    expect(typeof result.issuedToken).toBe("string");
  });

  test("authorize consumes code (single use)", () => {
    const pm = makePairing();
    const code = pm.rotateCode();

    pm.authorize("client1", code);
    const result = pm.authorize("client2", code);
    expect(result.ok).toBe(false);
    expect(result.error).toBe("E_PAIRING_INVALID");
  });

  test("authorize with token works after pairing", () => {
    const pm = makePairing();
    const code = pm.rotateCode();

    const first = pm.authorize("client1", code);
    expect(first.ok).toBe(true);

    const second = pm.authorize("client1", undefined, first.issuedToken!);
    expect(second.ok).toBe(true);
  });

  test("authorize with wrong token fails", () => {
    const pm = makePairing();
    const code = pm.rotateCode();
    pm.authorize("client1", code);

    const result = pm.authorize("client1", undefined, "wrong-token");
    expect(result.ok).toBe(false);
    expect(result.error).toBe("E_PAIRING_INVALID");
  });

  test("authorize with no credentials fails", () => {
    const pm = makePairing();
    const result = pm.authorize("client1");
    expect(result.ok).toBe(false);
    expect(result.error).toBe("E_PAIRING_REQUIRED");
  });

  test("expired code fails", () => {
    const pm = makePairing(0); // 0s TTL = immediately expired
    pm.rotateCode();

    const result = pm.authorize("client1", "WHATEVER");
    expect(result.ok).toBe(false);
  });
});
