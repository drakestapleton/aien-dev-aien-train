# tune4 receipts (`ollm tune4 CK OUT TOTAL LRMICRO [T B G]`)

Check: [`tests/omegallm/tune4-check.sh`](../../../../tests/omegallm/tune4-check.sh). Host CPU, core 6.

Command (from the repository root; scratch on /dev/shm, deleted by the script):

    TMPDIR=/dev/shm/hive/ownmodel/fixes-tune4 OMC=<pinned omc> taskset -c 6 nice -n 10 sh tests/omegallm/tune4-check.sh

omc sha256 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f (omega-mv e5b32567, the aarch64 pin).

| Run | Source | ollm sha256 | Result | rc | UTC |
|---|---|---|---|---|---|
| pre-fix | 915d9b8 (integ3) + the check | 9e6441d4bad0c65ff1a972d3b6d1b8c7e8d1d82993e3f96e371c4a3a35574ba7 | `TUNE4_CHECK FAIL failed=2 of n=124` | 1 | 2026-11-07T06:42:45Z .. 06:46:06Z |
| post-fix | a647e11 (xtunes re-checks xgeom) | 7137cef83bc553ecf698c874feb5183bf1a3835783480e53a2e634b2e290987b | `TUNE4_CHECK PASS n=124` | 0 | 2026-11-07T06:46:26Z .. 06:48:53Z |

Full outputs: `prefix-output.txt` / `prefix-rc.txt` / `prefix-date.txt` and `output.txt` / `rc.txt` / `date.txt`.
The pre-cfec44b reference build (`git archive cfec44b^` = 9348173) has ollm sha256
7cb31846a05f540683f2fac6e1161335634e5a7c9badda36965b8d7805e995bf.

What is checked (CK03 header offsets from v4.om xhdr; byte ranges with `cmp -i -n`, zero ranges against /dev/zero):
- Input V32768 T256 D32 H2 F64 L2 B4 G2 (P 1,065,120), one `train4` step so Adam m, v are nonzero (asserted).
- tune4 to T512 B8 G4, to T256 B8 G8, and the 6-argument form: magic, V, D H F L, seed, P, rope base and params
  (8P bytes) byte-identical to the input; m and v (16P bytes) all zero; step 0; T B G, TOTAL and lr bits
  (f64(LRMICRO/10^6), Wolfram) as given; size 128 + 24P. T512 output: `eval4` rc 0 and one `train4` step keeps T B G.
- `eval4` token mode on 8192 fixed u16 tokens (first 16384 bytes of LICENSE): W, loss and bits per token equal to the
  input's at unchanged T (the step field is 0 vs 1, since tune4 resets the step).
- 6-argument output byte-identical to the cfec44b^ build's tune4 (which refuses T B G with 2).
- Boundaries T2 B1 G1, T16384 B4096 G4096, T16384 B4096 G1 accepted and reloadable.
- Exit 12 and no output file: T 0, 1, 16385; B 0, 4097; G 0; G > B; B mod G != 0 (6/4, 8/3); TOTAL 0. 7 or 8 arguments: 2.
- v3 OLLMCK01 and OLLMCK02 (from `init`, `init ... G`) with T B G: exit 2, no output; 6 arguments run v3 tune.

Negative controls (all in the PASS run): a copy of the T512 output with one flipped param byte fails the params
`cmp`; one with a nonzero Adam v byte fails the zero `cmp`; that copy is refused on load (FNV, 14); a source mutant
(xtunes `put xg 6 g2` instead of `b2`) writes B 4 and fails the B check. The pre-fix run is itself a failing run.

Spec item that failed before the fix (section 5b): for V256 T256 D512 H8 F64 L1, `tune4 ... 16384 4 2` returned 0
and wrote a CK03 that every load refuses with 12 (decode layout 8D + 2F + 4 + V + T + 2TD > OAC; `init4` refuses
that shape with 12). Fix a647e11: xtunes runs xgeom on the new header and exits 12 before saving.

NOT_RUN: v4-wide-check.sh (heavy; it only uses the 6-argument tune4, which the byte-identity check covers),
GB10 paths, x86 targets.
