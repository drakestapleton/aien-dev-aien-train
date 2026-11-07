/-! DRA-23 dra23live verdict model (si023, Hermes worker claude-opus-5-5).
Explicit model of harness/live.om's decision logic (gpuchk, fail counting, verdict), not the code
itself. Checked 2026-11-07 with the lean MCP (Lean 4, lean-lsp-mcp): success, axioms
pass_safe [propext, Classical.choice, Quot.sound]; mixed_iff_two_classes [propext];
mixed_never_pass [propext]. Control: `theorem bad : mixedFail 3 = false := by decide` is rejected
("decide proved that the proposition mixedFail 3 = false is false"). -/

/-- gpuchk: fail tr5 when g has two or more bits (bits as gclass sets them: 1 nvrm, 2 aiengpu, 4 drm, 8 accel/kfd). -/
def mixedFail (g : Nat) : Bool := g != 0 && (g &&& (g - 1)) != 0

def single (g : Nat) : Bool := g != 0 && (g &&& (g - 1)) == 0

/-- For every value the gclass accumulation can reach (g < 16), the tr5 test fires exactly when
    more than one backend class was observed. -/
theorem mixed_iff_two_classes : ∀ g : Fin 16,
    mixedFail g.val = true ↔ (g.val ≠ 0 ∧ g.val ≠ 1 ∧ g.val ≠ 2 ∧ g.val ≠ 4 ∧ g.val ≠ 8) := by
  decide

structure Obs where
  holders : Nat
  exeMatch : Bool
  soMapped : Nat
  gseen : Nat
  gexp : Nat
  filesOk : Bool
  httpOk : Bool
  procOk : Bool

/-- number of fail lines main can emit for these observations (tr1 ends the run early) -/
def fails (o : Obs) : Nat :=
  if o.holders ≠ 1 then 1 else
  (if o.exeMatch then 0 else 1) + o.soMapped + (if mixedFail o.gseen then 1 else 0)
  + (if o.gseen = o.gexp then 0 else 1) + (if o.filesOk then 0 else 1)
  + (if o.httpOk then 0 else 1) + (if o.procOk then 0 else 1)

def pass (o : Obs) : Prop := fails o = 0

/-- Safety: PASS implies exactly one holder, matching exe, no shared object, the observed GPU
    class equals the declared one, and (expectations none/nvrm/aiengpu = 0/1/2) that class is
    none or a single backend. -/
theorem pass_safe (o : Obs) (hexp : o.gexp = 0 ∨ o.gexp = 1 ∨ o.gexp = 2) (h : pass o) :
    o.holders = 1 ∧ o.exeMatch = true ∧ o.soMapped = 0 ∧ o.gseen = o.gexp ∧
    o.filesOk = true ∧ o.httpOk = true ∧ (o.gseen = 0 ∨ single o.gseen = true) := by
  unfold pass fails at h
  by_cases h1 : o.holders ≠ 1
  · simp [h1] at h
  · simp only [h1, ite_false] at h
    have hx : o.exeMatch = true := by
      cases hh : o.exeMatch <;> simp_all
    have hg : o.gseen = o.gexp := by
      by_cases hq : o.gseen = o.gexp
      · exact hq
      · simp [hq] at h <;> omega
    have hf : o.filesOk = true := by cases hh : o.filesOk <;> simp_all
    have ht : o.httpOk = true := by cases hh : o.httpOk <;> simp_all
    have hs : o.soMapped = 0 := by omega
    refine ⟨by omega, hx, hs, hg, hf, ht, ?_⟩
    rcases hexp with e | e | e <;> rw [hg, e] <;> decide

/-- Negative control: two classes observed (nvrm + aiengpu = 3) never PASS. -/
theorem mixed_never_pass (o : Obs) (hg : o.gseen = 3) : ¬ pass o := by
  unfold pass fails
  by_cases h1 : o.holders ≠ 1
  · simp [h1]
  · simp only [h1, ite_false, hg]
    have : mixedFail 3 = true := by decide
    simp [this]

#print axioms pass_safe
#print axioms mixed_iff_two_classes
#print axioms mixed_never_pass
