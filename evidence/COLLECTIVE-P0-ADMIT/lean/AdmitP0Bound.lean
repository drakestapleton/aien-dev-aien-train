/-
DRA-15 / aien-train#26 P0 admission (Spark hive card t_8cf72aaf).
Safety invariant behind the out_of_range guard (-15) of
native/collective/admit_p0.om: once admission returned 0, no intermediate
of the response computation leaves signed 64-bit range, so the checked
arithmetic of the seeded compiler (trap 1) can never fire on an admitted job.

Model (hand-copied from admit_p0.om at this commit; checked by reading):
  VMAX = 65536 (const VMAX), active budget <= 3 (const KMAX, guard -11);
  fn bxrow : s := 0; s := s + B[r,c] * x[c] for c = 0,1,2;
  fn vdot  : dot := 0; dot := dot + V[c] * x[c] for c = 0,1,2;
  fn compute, per planned slot j < k: f := phase * dot; d := f * U[r];
             acc[r] := acc[r] + d, starting from acc[r] = bxrow r;
  phase in {1, -1} (guard -3); every entry of x, B and of the planned
  candidates' U, V in [-VMAX, VMAX] (guard -15).
Wolfram: 3 * 65536^2 + 9 * 65536^3 = 2533287675297792 < 2^63 - 1.
-/
import Mathlib.Tactic

namespace AdmitP0

def M : ℤ := 65536
def fits64 (v : ℤ) : Prop := -(2:ℤ)^63 ≤ v ∧ v ≤ (2:ℤ)^63 - 1
/-- ceiling on every intermediate: 3 M^2 + 9 M^3 -/
def C : ℤ := 3 * M^2 + 9 * M^3

lemma mulb {a b A B : ℤ} (ha : |a| ≤ A) (hb : |b| ≤ B) : |a * b| ≤ A * B := by
  rw [abs_mul]
  exact mul_le_mul ha hb (abs_nonneg _) ((abs_nonneg _).trans ha)

lemma addb {a b A B : ℤ} (ha : |a| ≤ A) (hb : |b| ≤ B) : |a + b| ≤ A + B :=
  (abs_add_le a b).trans (add_le_add ha hb)

lemma fitsC {v : ℤ} (h : |v| ≤ C) : fits64 v := by
  have hC : C = 2533287675297792 := by norm_num [C, M]
  rw [hC, abs_le] at h
  unfold fits64
  constructor <;> norm_num <;> linarith [h.1, h.2]

/-- bxrow and vdot: every prefix sum of a 3-term dot product fits, and the
    full sum is at most 3 M^2 in magnitude. -/
theorem dot3 (a b : Fin 3 → ℤ) (ha : ∀ i, |a i| ≤ M) (hb : ∀ i, |b i| ≤ M) :
    fits64 (a 0 * b 0) ∧ fits64 (a 0 * b 0 + a 1 * b 1) ∧
    fits64 (a 0 * b 0 + a 1 * b 1 + a 2 * b 2) ∧
    |a 0 * b 0 + a 1 * b 1 + a 2 * b 2| ≤ 3 * M^2 := by
  have t : ∀ i, |a i * b i| ≤ M * M := fun i => mulb (ha i) (hb i)
  have h1 := t 0
  have h2 := addb (t 0) (t 1)
  have h3 := addb h2 (t 2)
  have hM : M * M = 4294967296 := by norm_num [M]
  have hC : C = 2533287675297792 := by norm_num [C, M]
  refine ⟨fitsC ?_, fitsC ?_, fitsC ?_, ?_⟩
  · rw [hC]; linarith
  · rw [hC]; linarith
  · rw [hC]; linarith
  · have : (3:ℤ) * M^2 = 12884901888 := by norm_num [M]
    rw [this]; linarith

/-- One planned adapter slot j < 3 of compute preserves the invariant
    |acc| <= 3 M^2 + j * 3 M^3, and every value it forms fits. -/
theorem step (acc : ℤ) (j : ℕ) (hj : j < 3)
    (hacc : |acc| ≤ 3 * M^2 + (j : ℤ) * (3 * M^3))
    (v x : Fin 3 → ℤ) (u ph : ℤ) (hv : ∀ i, |v i| ≤ M) (hx : ∀ i, |x i| ≤ M)
    (hu : |u| ≤ M) (hph : ph = 1 ∨ ph = -1) :
    fits64 (ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2)) ∧
    fits64 (ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2) * u) ∧
    fits64 (acc + ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2) * u) ∧
    |acc + ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2) * u| ≤
      3 * M^2 + ((j : ℤ) + 1) * (3 * M^3) := by
  obtain ⟨-, -, -, hd⟩ := dot3 v x hv hx
  have hp : |ph| ≤ 1 := by rcases hph with h | h <;> simp [h]
  have hf : |ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2)| ≤ 1 * (3 * M^2) := mulb hp hd
  have hdd : |ph * (v 0 * x 0 + v 1 * x 1 + v 2 * x 2) * u| ≤ 1 * (3 * M^2) * M := mulb hf hu
  have hj' : (j : ℤ) ≤ 2 := by omega
  have hC : C = 2533287675297792 := by norm_num [C, M]
  have e2 : (3:ℤ) * M^2 = 12884901888 := by norm_num [M]
  have e3 : (3:ℤ) * M^3 = 844424930131968 := by norm_num [M]
  have e1 : (1:ℤ) * (3 * M^2) * M = 844424930131968 := by norm_num [M]
  rw [e2, e3] at hacc
  rw [e2] at hf
  rw [e1] at hdd
  have hs := addb hacc hdd
  refine ⟨fitsC ?_, fitsC ?_, fitsC ?_, ?_⟩
  · rw [hC]; linarith
  · rw [hC]; linarith
  · rw [hC]; nlinarith
  · rw [e2, e3]; nlinarith

/-- Initial state: acc = bxrow r satisfies the invariant with j = 0. -/
theorem init (b x : Fin 3 → ℤ) (hb : ∀ i, |b i| ≤ M) (hx : ∀ i, |x i| ≤ M) :
    |b 0 * x 0 + b 1 * x 1 + b 2 * x 2| ≤ 3 * M^2 + ((0:ℕ) : ℤ) * (3 * M^3) := by
  obtain ⟨-, -, -, h⟩ := dot3 b x hb hx
  simpa using h

/-- The ceiling itself fits; this is where the budget KMAX = 3 is used. -/
theorem ceiling_fits : C ≤ (2:ℤ)^63 - 1 := by norm_num [C, M]

/-- Negative control 1: with a range bound of 2^20 instead of 2^16 the same
    ceiling no longer fits, so the guard's constant is load-bearing. -/
theorem looser_bound_overflows : ¬ (3 * ((2:ℤ)^20)^2 + 9 * ((2:ℤ)^20)^3 ≤ (2:ℤ)^63 - 1) := by
  norm_num

/-- Negative control 2: the ceiling is attained (all entries M, phases +1,
    three adapters), so it is not slack: y = 3 M^2 + 3 * (3 M^2) * M. -/
theorem ceiling_attained : 3 * M * M + 3 * ((M * M + M * M + M * M) * M) = C := by
  norm_num [C, M]

end AdmitP0

#print axioms AdmitP0.dot3
#print axioms AdmitP0.step
#print axioms AdmitP0.init
#print axioms AdmitP0.ceiling_fits
#print axioms AdmitP0.looser_bound_overflows
#print axioms AdmitP0.ceiling_attained
