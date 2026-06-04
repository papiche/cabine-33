# Deterministic Personal Phase Computation from Birth Ephemeris Data for Social Resonance Matching

**Authors:** Frédéric Renault  
**Institution:** G1FabLab / UPlanet ORIGIN  
**License:** Creative Commons Attribution 4.0  
**Project:** https://opencollective.com/monnaie-libre  
**Code:** https://github.com/papiche/Astroport.ONE (AGPL-3.0)

---

## Abstract

This disclosure describes a method for computing a deterministic personal phase value φ_i from birth data (date, time, geographic coordinates) without storing biometric information centrally.

Formula: φ_i = fmod(T_birth_UTC, T_year) / T_year × 2π + (lon_birth / 360) × T_day + Δφ_pentagon

Where T_year = 365.25636 × 86400 s (sidereal year), T_day = 86400 s, and Δφ_pentagon is an offset derived from the nearest pentagonal node of a Goldberg polyhedron GP(n,m) tessellation of the Earth (12 nodes at icosahedral symmetry axes).

A pairwise resonance metric k = 1 / (1 + |sin(φ_i − φ_j)|) measures harmonic alignment between two individuals, k ∈ [0.5, 1.0]. Values k ≥ 0.95 define a constructive interference zone (optical singularity).

Applications: (1) proximity-based social matching in decentralized NOSTR peer-to-peer networks, (2) deterministic cryptographic key seeding — same birth inputs always yield the same φ_i, enabling key reproducibility without central storage, (3) geographic anchor points via Goldberg pentagon framework for hexagonal cell addressing tied to orbital mechanics.

Combined with Shamir Secret Sharing (2-of-3 threshold), this enables cryptographic key recovery without biometric hardware or central databases.

Prior art: Goldberg polyhedra (Goldberg, 1937), sidereal orbital mechanics (standard astronomy). No prior combination for social resonance computation or cryptographic key derivation is known to the authors.

---

## 1. Background

Existing social matching systems rely on explicit user-declared attributes (interests, location, age) stored in centralized databases. Cryptographic identity systems typically require biometric hardware (fingerprint readers, iris scanners) or government-issued documents as root of trust.

This disclosure presents an alternative: a personal phase value derived mathematically from immutable birth circumstances, computed locally on-device, producing the same result deterministically on any device given the same inputs.

---

## 2. Personal Phase Formula

### 2.1 Input Parameters

| Parameter | Type | Precision | Notes |
|-----------|------|-----------|-------|
| `birth_unix_utc` | integer | seconds | Unix timestamp at birth, UTC-corrected |
| `birth_lon` | float | degrees | Birth longitude, range [-180, +180] |
| `birth_lat` | float | degrees | Birth latitude, range [-90, +90] |

### 2.2 Constants

```
T_YEAR  = 365.25636 × 86400  = 31,558,149.504 seconds  (sidereal year)
T_DAY   = 86400               seconds
TAU     = 2π                  ≈ 6.283185307
```

### 2.3 Computation Steps

**Step 1 — Orbital phase (position in sidereal year):**
```
phase_orbital = fmod(birth_unix_utc, T_YEAR) / T_YEAR × TAU
```
This maps the birth Unix timestamp to an angle [0, 2π] within the sidereal year, independent of calendar conventions.

**Step 2 — Solar longitude correction:**
```
solar_correction = (birth_lon / 360.0) × T_DAY
```
Converts geographic longitude to a time offset (seconds), accounting for local solar time at birth.

**Step 3 — Recompute with corrected timestamp:**
```
corrected_unix = birth_unix_utc + solar_correction
phase_solar    = fmod(corrected_unix, T_YEAR) / T_YEAR × TAU
```

**Step 4 — Pentagon offset (Continuous Inverse-Square Weighted Circular Average):**

The Earth surface is tessellated using a Goldberg polyhedron GP(n,m). The 12 pentagonal nodes correspond to the 12 vertices of the underlying icosahedron projected onto the sphere.

Rather than a discrete snap to the nearest pentagon (which would introduce artificial Voronoi-boundary discontinuities in the phase field), the system computes a **continuous scalar phase field** via inverse-square weighted circular averaging over all 12 pentagon nodes simultaneously:

```
for k in {0..11}:
    d_k      = haversine_distance(birth_lat, birth_lon, pentagon_k)
    weight_k = 1.0 / (d_k² + ε)          [ε = 0.0001 km² for numerical stability]
    angle_k  = (k / 12) × 2π

sum_sin    = Σ_k (sin(angle_k) × weight_k)
sum_cos    = Σ_k (cos(angle_k) × weight_k)
Δφ_pentagon = atan2(sum_sin, sum_cos)     [result ∈ (-π, π], mapped to [0, 2π)]
```

This algorithm ensures the geographic phase field is mathematically smooth and continuous across the entire planetary surface. A point equidistant from two pentagons receives a blended phase between them, rather than a hard boundary. The `atan2(Σsin, Σcos)` formulation avoids wrap-around artifacts that would arise from averaging angles directly.

**Step 5 — Wave stretch and final personal phase:**
```
wave_stretch = F_PHI / F_2            [= 33.17 / 31.32 ≈ 1.059, Phi2X ratio]
φ_i = fmod((phase_solar + Δφ_pentagon) × wave_stretch, TAU)
```

The `wave_stretch` factor applies the F_PHI/F_2 ratio as a continuous wave compression/expansion parameter, not as a topological modulus. The final modulo TAU (2π) ensures φ_i spans the full circle, which is required for both constructive (Δφ≈0) and destructive (Δφ≈π) interference conditions to be reachable.

**Musical correspondence:** The wave_stretch value of F_PHI/F_2 = 33.17/31.32 ≈ 1.05919 is within 0.02% of 2^(1/12) ≈ 1.05946 — the mathematical ratio of a chromatic semitone in equal temperament (the twelfth root of two). This near-identity is not arithmetically enforced but emerges from the physiological frequency constants F_PHI and F_2. It connects the spatial phase field directly to the harmonic structure of Western music theory (Pythagoras's "Music of the Spheres"), where the 12 chromatic intervals map naturally onto the 12 pentagonal nodes of the Goldberg tessellation.

Range: φ_i ∈ [0, 2π)

---

## 3. Resonance Metric

Given two individuals with personal phases φ_i and φ_j:

```
k = 1 / (1 + |sin(φ_i − φ_j)|)
```

Properties:
- k ∈ [0.5, 1.0] always
- k = 1.0 when Δφ = 0 (constructive interference) **or** Δφ = π (destructive interference / optical vortex)
- k = 0.5 when Δφ = π/2 or 3π/2 (maximum dissonance)
- k ≥ 0.95 defines the "optical singularity" zone (both alignment and opposition conditions)
- The metric is symmetric: k(i,j) = k(j,i)
- Continuous and differentiable everywhere

The optical singularity threshold k ≥ 0.95 corresponds to |Δφ| < arcsin(1/20) ≈ 2.87°, approximately 1/125th of a full orbital cycle, or about 2.9 days of sidereal year.

---

## 4. Cryptographic Key Derivation

The deterministic nature of φ_i enables cryptographic applications.

### 4.1 Cryptographic Key Seeding

The same birth and conception ephemeris parameters used to compute φ_i can be formatted into two canonical ASCII strings — a `SALT` (birth data) and a `PEPPER` (conception data) — and fed into a Key Derivation Function (KDF) to generate a secp256k1 private key deterministically. The same inputs always yield the same key, enabling recovery on any device without central storage.

### 4.2 SSSS Key Recovery Integration

The resulting 32-byte seed can be split using Shamir's Secret Sharing (2-of-3 threshold) across a cooperative network topology (user device / local node / network hub). This entire cryptographic protocol — including the exact SALT and PEPPER string formats, the biometric conception offset formula `gestation_days = 280.0 + (birth_weight_kg − 3.5) × 4.0`, and the SSSS share distribution model — is extensively detailed in the companion disclosure: *"Biometric Birth Ephemeris as Deterministic Parameters for Shamir Secret Sharing Key Recovery"* (same series, same authors).

---

## 5. Geographic Hexagonal Integration

The Goldberg polyhedron tessellation provides a hierarchical geographic addressing system. Each hexagonal cell is addressed by its axial coordinates (q, r) within the local pentagon frame.

The φ_i pentagon offset creates a natural geographic clustering: individuals born near the same pentagon vertex share similar phase offsets, creating geographic resonance zones independent of calendar date effects.

This property is exploited for proximity-based social matching: two individuals with high k values AND born near the same geographic pentagon are predicted to have stronger social resonance than high-k pairs from different pentagon zones.

---

## 6. Implementation Reference

A reference implementation in GDScript (Godot 4.x) is available in the open-source project ATOM4LOVE / Cabine-33 under AGPL-3.0 license:

```gdscript
func compute_personal_phase(birth_unix: int, birth_lon: float,
                             birth_lat: float, utc_offset_h: float) -> float:
    var T_YEAR: float = 365.25636 * 86400.0
    var T_DAY: float  = 86400.0
    var TAU: float    = TAU  # 2π

    # UTC correction
    var birth_unix_utc: int = birth_unix - int(utc_offset_h * 3600.0)

    # Solar longitude correction
    var solar_corr_s: float = (birth_lon / 360.0) * T_DAY
    var corrected: float    = float(birth_unix_utc) + solar_corr_s

    # Orbital phase
    var phase: float = fmod(corrected, T_YEAR) / T_YEAR * TAU

    # Pentagon offset
    var penta_data: Dictionary = get_nearest_pentagon(birth_lat, birth_lon, birth_unix_utc)
    var penta_id: int          = penta_data.get("pentagon_id", 0)
    var penta_offset: float    = float(penta_id) / 12.0 * TAU

    return fmod(phase + penta_offset, TAU)
```

A Python implementation is available in `Astroport.ONE/tools/kin_oracle.sh` (bash) and associated Python scripts under the same AGPL-3.0 license.

---

## 7. Prior Art and Novelty

**Known prior art:**
- Goldberg polyhedra: Goldberg, M. (1937). "A class of multi-symmetric polyhedra." Tohoku Mathematical Journal. 43: 104–108.
- Sidereal year computation: standard astronomical ephemeris (VSOP87, IAU standards)
- Shamir Secret Sharing: Shamir, A. (1979). "How to share a secret." Communications of the ACM. 22(11): 612–613.
- PBKDF2: RFC 2898 (2000)

**Novel combination:**
No prior art is known to the authors combining:
1. Sidereal orbital phase from birth Unix timestamp
2. Solar longitude correction from geographic birth coordinates
3. Goldberg pentagon offset as phase anchor
4. Resulting scalar φ_i used as both social resonance metric input AND cryptographic key seed

The resonance metric k = 1/(1 + |sin(Δφ)|) applied to birth-derived phases for social matching is believed to be novel.

---

## 8. Claims of Novelty

This disclosure establishes prior art for the following concepts:

1. Computing a personal phase φ_i from {birth_unix_utc, birth_lon, birth_lat} using sidereal year modulo and solar longitude correction.

2. Computing a continuous geographic phase offset Δφ_pentagon via inverse-square exponentially-weighted circular averaging (`exp(−d/1500)` decay) over all 12 icosahedral pentagon nodes, producing a smooth scalar phase field without Voronoi boundary discontinuities.

3. The assignment of sequential angular values `(k/12) × 2π` to spatially distributed icosahedral vertices creates a pseudo-random cryptographic geographic phase hash: adjacent geographic zones receive non-adjacent phase values, enhancing birth-location privacy while maintaining full deterministic reproducibility.

4. Computing a social resonance metric k = 1/(1 + |sin(Δφ)|) as a **phase folding function** that simultaneously identifies both constructive interference (Δφ≈0, k→1) and destructive interference / optical vortex (Δφ≈π, k→1) as high-resonance states, unifying both singularity types in a single bounded scalar metric.

5. Using the deterministic φ_i computation as input to a cryptographic key derivation function, enabling reproducible key generation from birth data without central storage.

6. Combining the physiological water resonance frequency F_water (429.62 Hz) with the Phi2X differential F_Φ (33.17 Hz) as a binaural acoustic entrainment mechanism to biologically anchor the mathematically computed personal phase during location-based proof-of-presence rituals (see companion Disclosure 2).

7. Combining (1)-(5) with Shamir Secret Sharing (2,3) for distributed key recovery without biometric hardware (see companion Disclosure 3).

---

*This disclosure is submitted for defensive publication purposes only. The authors do not seek patent protection for the described methods and explicitly place this disclosure in the public domain of prior art.*
