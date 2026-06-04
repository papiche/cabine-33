# Tzolkin Kin-Based Oracle Matrices Combined with Phase Interference Metrics for Decentralized Social Coordination

**Authors:** Frédéric Renault  
**Institution:** G1FabLab / UPlanet ORIGIN  
**License:** Creative Commons Attribution 4.0  
**Code:** https://github.com/papiche/Astroport.ONE (AGPL-3.0)

---

## Abstract

This disclosure describes a social coordination system combining a mathematical projection of the Maya Tzolkin calendar (260-day cycle, 20 seals × 13 tones) with a continuous wave-phase interference metric for peer-to-peer social matching in decentralized networks without centralized social graphs.

The Kin computation uses a 52-year modulo lookup mechanism (KIN_MESES monthly offset array + KIN_SUMA 52-year cycle dictionary) rather than standard Julian Day conversions, providing a computationally efficient and offset-correctable mapping from Gregorian dates to Tzolkin Kin numbers.

The resonance metric `k = 1 / (1 + |sin(Δφ)|)` operates on personal phase values φ_i derived from birth ephemeris. Critically, the "optical singularity" state (super-coherence, k ≥ 0.95) is triggered under **two** distinct boundary conditions:
1. `Δφ < ε` — constructive interference (perfect alignment)
2. `|Δφ − π| < ε` — destructive interference (optical vortex / phase opposition)

Both conditions correspond to physically meaningful wave interference states, and both produce k ≥ 0.95. Their combination creates a richer social matching topology than alignment-only systems.

Applications include automated newsletter-based social introductions (KIN.news, KIN.daily), real-time proximity bonding events via local Bluetooth/WiFi beacons, and WoTx2 peer validation without centralized profiling.

---

## 1. Background

Existing social matching platforms rely on declared interests (keywords, categories), behavioral data mining, or simple demographic proximity. The system described here derives matching potential from immutable birth data (Kin number, personal phase φ_i) and computes resonance continuously from proximity data, requiring neither user-declared attributes nor behavioral tracking.

---

## 2. Algorithmic Kin Computation

### 2.1 Standard vs. Matrix Approach

The standard method for computing a Tzolkin Kin number from a Gregorian date requires a reference Julian Day Number (JDN) and modular arithmetic on the Julian day count. This approach requires either a floating-point JDN computation or a large lookup table for all dates.

The disclosed system uses a 52-year cycle structure that avoids JDN computation entirely:

```
kin = (day + KIN_MESES[month - 1] + KIN_SUMA[year % 52]) mod 260
if kin == 0: kin = 260
```

### 2.2 KIN_MESES — Monthly Offset Array

`KIN_MESES` is a 12-element integer array providing the cumulative Tzolkin offset for each calendar month within a reference year:

```
KIN_MESES = [0, 31, 59, 90, 120, 151, 181, 212, 243, 13, 44, 74]
```

Each value represents the number of days elapsed from the start of the reference year to the first day of the corresponding month, taken modulo 260. The values for months 10-12 wrap around (e.g., 273 mod 260 = 13 for October).

Note: this array encodes a non-leap-year reference. For leap years, months after February receive an additional offset of +1 (applied at computation time when `month > 2` and `is_leap_year(year)`).

### 2.3 KIN_SUMA — 52-Year Cycle Dictionary

`KIN_SUMA` is a dictionary mapping `year % 52` to the Tzolkin offset for the first day of that year in the 52-year calendar cycle:

```python
KIN_SUMA = {
     0:   0,  1:  5,  2: 10,  3: 15,  4: 20,
     5:  25,  6: 30,  7: 35,  8: 40,  9: 45,
    10:  50, 11: 55, 12: 60, 13: 65, 14: 70,
    15:  75, 16: 80, 17: 85, 18: 90, 19: 95,
    20: 100, 21: 105,22: 110,23: 115,24: 120,
    25: 125, 26: 130,27: 135,28: 140,29: 145,
    30: 150, 31: 155,32: 160,33: 165,34: 170,
    35: 175, 36: 180,37: 185,38: 190,39: 195,
    40: 200, 41: 205,42: 210,43: 215,44: 220,
    45: 225, 46: 230,47: 235,48: 240,49: 245,
    50: 250, 51: 255
}
```

The 52-year cycle arises from the mathematical intersection of the 260-day Tzolkin and the 365-day Haab calendars: LCM(260, 365) = 18,980 days = 52 Haab years.

### 2.4 Derived Values

From a Kin number `k ∈ {1, ..., 260}`:

```
seal  = (k - 1) mod 20        # Solar seal, range [0, 19]
tone  = ((k - 1) mod 13) + 1  # Galactic tone, range [1, 13]
color = seal mod 4             # Color family, range [0, 3]: Red/White/Blue/Yellow
```

**Five Oracle Powers:**

| Power | Formula | Range |
|-------|---------|-------|
| Tonality | `tone` of kin | 1-13 |
| Analogue | `seal_a = (seal + 10) mod 20` → kin_a | 1-260 |
| Guide | `guide_table[tone][seal]` (20×13 lookup matrix) | 1-260 |
| Antipode | `seal_p = (seal + 10) mod 20`, `tone_p = 14 - tone` | 1-260 |
| Occult | `kin_o = 261 - k` | 1-260 |

The Guide lookup matrix encodes the specific relationship between tones and seals in the Wavespell structure of the Dreamspell calendar. The Guide changes with each tone, making it non-trivially computable without the matrix.

---

## 3. Wave-Phase Resonance Metric

### 3.1 Personal Phase

Each individual's personal phase φ_i ∈ [0, 2π) is computed from birth ephemeris as described in companion disclosure "Deterministic Personal Phase Computation from Birth Ephemeris Data for Social Resonance Matching" (same series, same authors).

### 3.2 Resonance Metric k

Given two individuals with personal phases φ_i and φ_j:

```
Δφ = |φ_i − φ_j|
k   = 1.0 / (1.0 + |sin(Δφ)|)
```

Properties:
- k ∈ [0.5, 1.0] always
- k = 1.0 when Δφ = 0 or Δφ = π (both singularity conditions)
- k = 0.5 when Δφ = π/2 or Δφ = 3π/2 (maximum dissonance)
- Symmetric: k(i,j) = k(j,i)
- Periodic with period π (due to |sin|)

---

## 4. Dual Optical Singularity (Super-Coherence)

### 4.1 Two Distinct Singularity Conditions

A "super-coherence" or "vortex state" is triggered when k ≥ 0.95, which occurs under two distinct physical conditions defined by a tolerance threshold `ε` (typical value: 0.05 radians):

**Condition A — Constructive Interference:**
```
Δφ < ε    (≈ 2.87° angular difference)
```
The two phase waves are nearly aligned. Their superposition produces amplified coherence — the social equivalent of resonant coupling in optics.

**Condition B — Destructive Interference (Optical Vortex):**
```
|Δφ − π| < ε    (phases nearly opposite)
```
The two phase waves are nearly in opposition (Δφ ≈ 180°). In wave optics, perfect phase opposition creates a **phase singularity** (optical vortex): a point of complete destructive interference where amplitude goes to zero and phase is undefined. In the social matching context, this encodes a complementary polarity pairing rather than a similarity pairing — a "yin-yang" resonance where the differences are maximally structured.

Both conditions yield k ≥ 0.95 due to the periodic symmetry of |sin|:
```
sin(0) = 0     → k = 1.0  (Condition A, exact)
sin(π) = 0     → k = 1.0  (Condition B, exact)
sin(ε) ≈ ε    → k ≈ 1 / (1 + ε) ≥ 0.95 for ε ≤ 0.053
```

### 4.2 Implementation

```gdscript
const SINGULARITY_TOLERANCE: float = 0.05  # radians

func is_singularity(phi_i: float, phi_j: float) -> bool:
    var delta: float = abs(phi_i - phi_j)
    # Condition A: constructive interference
    if delta < SINGULARITY_TOLERANCE:
        return true
    # Condition B: destructive interference / optical vortex
    if abs(delta - PI) < SINGULARITY_TOLERANCE:
        return true
    return false

func compute_resonance_k(phi_i: float, phi_j: float) -> float:
    var delta: float = abs(phi_i - phi_j)
    return 1.0 / (1.0 + abs(sin(delta)))
```

### 4.3 Physical Interpretation

In classical optics, a vortex beam carries orbital angular momentum. The intensity is zero at the singularity core, but the phase winds by ±2π around it. Applied to social resonance, the "Vortex state" (Condition B) encodes pairs whose phases are maximally complementary — not similar, but structurally opposed in a way that creates a stable, locked relationship (like spin-up / spin-down electron pairs or circularly polarized light in opposite helicities).

This distinction between "similar resonance" (A) and "complementary resonance" (B) creates two qualitatively different social bonding types both detectable by the same k metric.

---

## 5. Social Coordination System

### 5.1 Oracle Group Types

Given a population of N registered members, each with known Kin number and phase φ_i, the system automatically identifies six group types:

| Group Type | Matching Rule | Social Interpretation |
|------------|--------------|----------------------|
| Quatuor | Same tone (4 members) | Wavespell family |
| Analogue | seal_a matches (2 members) | Complementary seal |
| Guide | Guide relationship (2 members) | Mentorship direction |
| Antipode | Antipode relationship (2 members) | Creative tension |
| Occult | 261-k relationship (2 members) | Hidden power |
| Phi-resonant | k ≥ 0.95 (any pair) | Phase singularity bonding |

### 5.2 Newsletter Automation

A weekly digest (`KIN.news`) and daily personalized newsletter (`KIN.daily`) scan the registered member base for the above group types and generate curated introduction emails:

- Each email is personalized per recipient (not a broadcast)
- The recipient's own Oracle powers are prominently displayed
- Matched groups are presented with contextual Dreamspell interpretation
- Phi-resonant pairs receive specific notification when Condition A or Condition B applies

The system requires no central social graph: all matching is computed from public data (Kin number, φ_i) and member contact list without behavioral tracking.

### 5.3 Real-Time Proximity Matching

In the mobile application (ATOM4LOVE), local Bluetooth/WiFi beacon announcements include the device's Kin number and φ_i. Nearby devices continuously compute pairwise k values:

- k ≥ 0.95 + Condition A → "Resonance Encounter" notification
- k ≥ 0.95 + Condition B → "Vortex State" notification (different UI treatment)
- k ≥ 0.8 → passive proximity indicator (Geiger counter audio feedback, rate proportional to k)

---

## 6. WoTx2 Integration

High-k pairs who engage in a real-world interaction can validate the encounter on the NOSTR protocol:

- Kind 7 reaction with content `+N` (where N = ZEN reward amount) = validate resonance
- Kind 1984 = open a dispute (WoTx2 peer mediation)
- Kind 30503 = publish a skill credential verified by the encounter

The k value is embedded in the Kind 7 event as a tag, creating a public record of resonance strength without revealing the underlying φ_i values.

---

## 7. Prior Art and Novelty

**Known prior art:**
- Maya Tzolkin calendar: ancient Mesoamerican origin
- Dreamspell calendar: José Argüelles (1987, Thirteen Moon calendar reform)
- Wave interference / optical vortex theory: Nye and Berry (1974)
- NOSTR protocol: fiatjaf et al. (2020)
- Social matching by similarity: numerous prior art (OKCupid, Grindr, etc.)

**Novel combination:**
No prior art is known for:
1. The specific KIN_MESES + KIN_SUMA (52-year cycle) algorithmic mapping from Gregorian date to Tzolkin Kin without JDN computation
2. Combining Tzolkin Oracle powers (5 powers) with a continuous phase resonance metric k from birth ephemeris
3. Triggering social "super-coherence" on both constructive (Δφ≈0) AND destructive (Δφ≈π) phase interference conditions
4. Embedding the k value in NOSTR Kind 7 reactions for public resonance attestation

---

## 8. Claims of Novelty

1. The KIN_MESES (12-element monthly offset array) + KIN_SUMA (52-year cycle dictionary indexed by `year % 52`) method for computing Tzolkin Kin from Gregorian date without Julian Day Number.

2. The dual optical singularity condition for social super-coherence: Condition A (`Δφ < ε`) AND Condition B (`|Δφ − π| < ε`), both yielding k ≥ 0.95 via the metric `k = 1/(1 + |sin(Δφ)|)`.

3. The specific interpretation of Condition B as "optical vortex" social bonding (complementary resonance) distinct from Condition A (similar resonance), creating two qualitatively different high-k bonding types.

4. The combination of Tzolkin Oracle power matching (5 powers) with continuous φ_i-based resonance computation for automated weekly/daily social introduction newsletters without centralized behavioral profiling.

5. The use of the Tzolkin calendar's mathematical structure (260-day cycle, 20 seals × 13 tones, 52-year Calendar Round) as a **deterministic social graph partitioning function** for asynchronous peer-to-peer networks: rather than deriving social clusters from observed behavioral interactions (as in Facebook, LinkedIn, or Twitter graph algorithms), the system derives them from immutable birth parameters. This creates a social routing topology that is pre-computed, privacy-preserving, and manipulation-resistant — the Oracle powers (Analogue, Guide, Antipode, Occult) function as a mathematically-defined routing table for human social introductions, without any central authority controlling the graph structure.

6. The real-time embedding of KIN number and personal phase φ_i in local proximity broadcast beacons (Bluetooth/WiFi), enabling pairwise k-value computation between physically co-present individuals without requiring prior social network registration or server-side matching.

---

*This disclosure is submitted for defensive publication purposes only. The authors do not seek patent protection for the described methods and explicitly place this disclosure in the public domain of prior art.*
