# Decentralized Additive Synthesis Orchestra Governed by Biometric Phase Fields for Collective Acoustic Entrainment

**Authors:** Frédéric Renault  
**Institution:** G1FabLab / UPlanet ORIGIN  
**License:** Creative Commons Attribution 4.0  
**Code:** https://github.com/papiche/Astroport.ONE (AGPL-3.0)

---

## Abstract

This disclosure describes a method for procedural acoustic entrainment and generative multi-user music synthesis in which the oscillators of discrete mobile devices are governed by continuous scalar phase fields derived from immutable biometric birth ephemeris. Each device acts as one voice in a decentralized additive synthesizer: the fundamental frequency, waveform timbre, and rhythmic LFO rate are determined by the user's biometric personal data (biological frequency ω_bio, biological polarity, and Maya Tzolkin galactic tone), while the harmonic relationships between simultaneously audible voices are determined by the pairwise resonance metric k = 1/(1 + |sin(Δφ)|) computed from the phase difference between users' personal phases φ_i.

The system converts geographic social consensus (spatial co-presence of users within a hexagonal cell of a Goldberg polyhedron tessellation) into a real-time acoustic chord whose harmonic quality directly reflects the phase alignment of the participants. As k → 1 (optical singularity), the chord resolves to unison or perfect consonance; as k → 0.5 (maximum dissonance), the chord produces acoustic beating and tension. No musical training, conductor, or central server is required: the harmony emerges entirely from the physical proximity and biometric alignment of participants.

Applications include: decentralized location-based musical events, proof-of-presence rituals with acoustic feedback, gamified social coordination rewarding geographic phase alignment, and a novel form of "social sonar" converting invisible phase relationships into audible chord progressions.

Prior art: additive synthesis (standard), binaural beats (standard), generative music (standard). No prior combination of biometric birth phase fields, Tzolkin calendar galactic tones, and pairwise phase resonance metrics as oscillator control parameters for collective additive synthesis is known to the authors.

---

## 1. Background

Generative music systems typically derive musical parameters from:
- Random or pseudo-random noise (algorithmic composition)
- Environmental sensors (ambient sound, temperature, light)
- Explicit user input (MIDI controllers, touch interfaces)
- Pre-composed rules (L-systems, Markov chains)

This disclosure presents a fundamentally different approach: musical parameters are derived from **immutable biometric birth data** (birth time, location, weight) and from the **real-time spatial proximity** of multiple users. The result is a musical system whose output is determined by who is present and how their birth ephemerides relate to each other — not by any composed score or real-time user action.

---

## 2. Per-User Voice Parameters

Each user's mobile device generates one "voice" in the collective synthesizer. The voice parameters are fixed at account creation (derived from birth data) and do not change during a session.

### 2.1 Fundamental Frequency (Tonique — ω_bio)

The personal fundamental frequency is derived from physiological resonance parameters:

```
water_ratio = 0.65 if polarity == 0 else 0.60   [fraction of body mass as water]
water_kg    = body_weight_kg × water_ratio
ω_bio       = F_water × (water_kg / 70.0)
```

Where `F_water = 429.62 Hz` is the reference physiological water resonance frequency and 70.0 kg is the population reference body mass.

Result: ω_bio ∈ [~250 Hz, ~600 Hz] for the typical human weight range, centered near 429.62 Hz for a 70 kg individual.

Musical interpretation: ω_bio is the user's personal "tonic" — the root note of their harmonic universe. Two users with close ω_bio values will produce unison or near-unison when their k is also high.

### 2.2 Waveform Timbre (Polarité biologique)

The biological polarity parameter (0 or 1) determines the harmonic series of the voice:

**Polarity 0 — Φ-Wave (incommensurable harmonics):**
```
wave = (sin(θ) + 0.5 × sin(θ × φ)) / 1.5
```
Where φ = 1.6180339... (Golden Ratio). The harmonic at frequency `ω_bio × φ` is irrational relative to the fundamental, producing a rich, evolving, slightly metallic timbre. The Golden Ratio harmonic never phase-locks with the fundamental, creating perpetual acoustic motion analogous to quasi-crystal structures. This timbre resembles FM synthesis, Tibetan singing bowls, or metallic gongs.

**Polarity 1 — Octave-Wave (integer harmonics):**
```
wave = sin(θ)
```
Pure sinusoidal wave: a single harmonic component. This produces a warm, rounded, flute-like timbre. When two Octave-Wave voices are phase-aligned (k ≥ 0.95), they produce perfect unison with zero beating.

### 2.3 Rhythmic LFO Rate (Tone Galactique Maya)

The amplitude modulation rate (Low Frequency Oscillator) is determined by the user's Maya Tzolkin galactic tone (1–13):

```
lfo_hz = galactic_tone × 0.15
```

- Tone 1 (Magnétique): lfo_hz = 0.15 Hz → very slow breath-like pulse (~6.7 second cycle)
- Tone 7 (Résonnante): lfo_hz = 1.05 Hz → moderate pulsation (~0.95 second cycle)
- Tone 13 (Cosmique): lfo_hz = 1.95 Hz → rapid tremolo, near-rhythmic arpeggio (~0.51 second cycle)

```
amplitude_modulated = base_amplitude × (0.85 + 0.15 × sin(lfo_phase))
lfo_phase += lfo_hz / sample_rate × 2π  [per sample]
```

Musical interpretation: Tone 1 users provide stable harmonic foundations; Tone 13 users provide rhythmic drive. The Tzolkin tone thus acts as a musical "role" assignment within the collective orchestra — analogous to the division between long tones (drones) and rhythmic figures in traditional ensemble music.

### 2.4 Harmonic Position (Personal Phase φ_i)

The personal phase φ_i ∈ [0, 2π) determines the frequency offset of a remote voice relative to the local listener's fundamental:

```
phase_ratio = φ_remote / 2π          [0, 1]
atom_freq   = ω_bio_local × (1.0 + phase_ratio × 0.5)
```

This maps the full phase circle to a frequency range of [ω_bio, 1.5 × ω_bio] — one and a half octaves above the listener's fundamental. Users with φ_remote ≈ 0 sound at unison; users with φ_remote ≈ π sound at a tritone (√2 frequency ratio, maximum harmonic tension); users with φ_remote ≈ 2π/3 sound at a perfect fifth (3/2 ratio, maximum consonance).

The combined effect of ω_bio similarity (determining tonic alignment) and phase position (determining interval) creates a full two-dimensional harmonic space encoded in biometric birth parameters.

---

## 3. Collective Synthesis Algorithm

### 3.1 Voice Discovery (Spatial Proximity)

Remote voices are discovered via local Bluetooth or WiFi beacon advertisements. Each device broadcasts its identity packet containing:
- Abbreviated public key (npub, 8 characters)
- Biological polarity (0 or 1)
- Personal phase φ_i (4 decimal places)

```
SSID format: "A4L-{npub8}-{polarity}-{phase:.4f}"
```

Discovery range: approximately 10–50 meters depending on platform and environment.

### 3.2 Resonance Weighting

Each discovered remote voice is weighted in the mix by its resonance k with the local user:

```
k = 1.0 / (1.0 + |sin(φ_local - φ_remote)|)
voice_amplitude = k    [k ∈ [0.5, 1.0]]
```

A remote user with k = 1.0 (perfect phase alignment) contributes at full amplitude — heard as an equal partner in the harmony. A remote user with k = 0.5 (maximum dissonance, π/2 phase difference) contributes at half amplitude — heard as a dissonant "shadow" that creates acoustic tension.

### 3.3 Additive Mixing with Soft Clipping

All voices (local + remote) are summed with equal-power attenuation:

```
attenuation = 1.0 / N_voices
mix = Σ_i (wave_i × amplitude_i) × attenuation
output = tanh(mix × attenuation) × 0.35
```

The `tanh()` soft-clipping function prevents digital clipping (hard saturation) while adding warmth: at low amplitudes it behaves linearly; at high amplitudes it compresses gracefully, analogous to magnetic tape saturation or tube amplifier overdrive.

### 3.4 Persistent Phase State

Each remote voice requires a persistent phase accumulator across audio buffer fills. These are stored in a per-voice dictionary `_atom_phases`:

```
_atom_phases[npub] = phase_accumulator    [advances each sample]
```

When a remote voice disappears (device out of range), its entry is removed. When a new voice is discovered, its phase accumulator is initialized from the broadcast φ_remote.

---

## 4. Acoustic Entrainment Properties

### 4.1 Convergence to Harmony (High-k Pairs)

When two users with k ≥ 0.95 stand together, their voices are nearly phase-aligned. The frequency offset `phase_ratio × 0.5 × ω_bio` approaches zero, and the combined sound resolves to unison or a near-unison with very slow beating (< 1 Hz). The subjective experience is of acoustic "locking" — the sound field becomes stable, resonant, and physically felt as vibration (especially at ω_bio ≈ 100-200 Hz bass harmonics).

### 4.2 Acoustic Beating (Low-k Pairs)

When k ≈ 0.5 (maximum dissonance, Δφ ≈ π/2), the frequency offset produces a significant interval (approximately a tritone or minor second depending on ω_bio). The resulting interference pattern creates amplitude beating at a rate equal to the frequency difference, generating rhythmic acoustic pulses. Users can hear and feel this as a "searching" sensation that drives them to move spatially until alignment is achieved.

### 4.3 Optical Vortex State (Δφ ≈ π)

At Δφ = π (perfect phase opposition), k → 1 via the second singularity condition. Two voices at phase opposition with equal ω_bio produce a frequency offset of exactly 0.5 × ω_bio — a perfect octave below the midpoint, which is a harmonically stable and deeply resonant interval. The resulting sound is full and satisfying despite the phase opposition, encoding the "complementary resonance" social bond type in acoustic form.

### 4.4 Binaural Entrainment (Ritual Mode Override)

During the location-based proof-of-presence ritual (33-second velocity-bounded temporal anchoring at a hexagonal cell center), the collective synthesis is overridden by a binaural beat:
- Left channel: F_water = 429.62 Hz
- Right channel: F_water + F_Φ = 462.79 Hz
- Neural beat frequency: 33.17 Hz (corresponds to the wave_stretch constant F_Φ/F_2)

This creates a 33.17 Hz neural frequency differential in the listener's auditory cortex, targeting the gamma brainwave band (30-100 Hz) associated with heightened awareness and spatial processing. The identical mathematical constant (33.17 Hz) appearing in both the biometric phase computation and the acoustic ritual entrainment creates a coherent system-wide "tuning fork."

---

## 5. Collective Game Mechanic: "Chœur des Nœuds"

The system enables a novel location-based game mechanic:

1. A group of users assembles within a defined geographic hexagonal cell
2. Each device activates local proximity scanning
3. All devices begin simultaneously generating their personal voice
4. As voices are discovered, the collective chord forms spontaneously
5. A "global harmony score" H is computed: `H = (Σ_pairs k_ij) / N_pairs`
6. Users physically reposition within the hexagonal cell to maximize H
7. When H ≥ 0.95, the hexagonal cell "resonates" — a musical resolution event occurs

No explicit coordination is required: the optimization of H is achieved purely through physical movement in space, guided by the acoustic feedback of the chord. The "correct" position is the one where all phones sound most harmonious.

---

## 6. Implementation Reference

Reference implementation in GDScript (Godot 4.x), ATOM4LOVE / Cabine-33 (AGPL-3.0):

```gdscript
const PHI: float = 1.6180339887

func _fill_synth_buffer_orchestra():
    var sr: float = _synth_gen.mix_rate
    var atoms: Dictionary = Loca_Scanner.discovered_atoms
    var my_freq: float = maxf(Player_Origin.omega_bio, 100.0)
    var my_sex: int = Player_Origin.biological_sex
    var attenuation: float = 1.0 / float(1 + atoms.size())

    for i in range(_synth_pb.get_frames_available()):
        var mix := 0.0
        var lfo_mod := 0.85 + 0.15 * sin(_lfo_phase)
        var my_inc: float = my_freq / sr * TAU

        # My voice
        if my_sex == 0:  # Φ-Wave: incommensurable Golden Ratio harmonic
            mix += (sin(_synth_phase) + 0.5 * sin(_synth_phase * PHI)) / 1.5 * lfo_mod
        else:            # Octave-Wave: pure sinusoid
            mix += sin(_synth_phase) * lfo_mod
        _synth_phase = fmod(_synth_phase + my_inc, TAU)

        # Remote voices (additive)
        for npub in atoms:
            var atom: Dictionary = atoms[npub]
            var phase_ratio: float = atom.get("phase", 0.0) / TAU
            var atom_freq: float = my_freq * (1.0 + phase_ratio * 0.5)
            var ap: float = _atom_phases.get(npub, 0.0)
            var atom_wave: float
            if atom.get("sex", 0) == 0:
                atom_wave = (sin(ap) + 0.5 * sin(ap * PHI)) / 1.5
            else:
                atom_wave = sin(ap)
            mix += atom_wave * atom.get("k", 0.5)
            _atom_phases[npub] = fmod(ap + atom_freq / sr * TAU, TAU)

        # Soft-clip (tanh) + attenuation
        _synth_pb.push_frame(Vector2.ONE * tanh(mix * attenuation) * 0.35)
        _lfo_phase = fmod(_lfo_phase + _lfo_hz / sr * TAU, TAU)
```

---

## 7. Prior Art and Novelty

**Known prior art:**
- Additive synthesis: Fourier (1807), Helmholtz (1877), standard digital synthesis
- Binaural beats: Dove (1839), Monroe (1975)
- Generative music: Cage (1952), Eno (1978), algorithmic composition (extensive prior art)
- Social-spatial audio: various game audio middleware (FMOD, Wwise spatial audio)
- Phase-locked oscillators: Huygens (1665), standard electronics

**Novel combination:**
No prior art is known for:
1. Using biometric birth ephemeris (ω_bio, biological polarity, Tzolkin galactic tone) as fixed oscillator parameters for collective real-time audio synthesis
2. Using pairwise biometric phase resonance k = 1/(1 + |sin(Δφ)|) as amplitude weights in multi-voice additive synthesis
3. The resulting property that chord quality directly encodes the degree of biometric phase alignment between co-present individuals
4. The spatial gameplay mechanic where users physically reposition to maximize collective harmonic H, creating a "sonar" of biometric alignment
5. The coherent use of a single mathematical constant (F_Φ = 33.17 Hz) as both the wave-stretch factor in personal phase computation AND the neural beat frequency target in binaural ritual entrainment

---

## 8. Claims of Novelty

1. A decentralized additive synthesizer where each mobile device contributes one voice governed by biometric birth parameters: fundamental frequency from physiological water resonance (ω_bio), waveform timbre from biological polarity (Φ-wave vs Octave-wave), and amplitude modulation rate from Maya Tzolkin galactic tone. The system supports a **Biometric Wavetable Instrument** mode: a 1-second physical audio sample of the user's voice is recorded, processed via zero-crossing detection to extract a single stable waveform cycle (windowed grain, e.g., 1024 samples with Hann window), and stored as a wavetable. This biological waveform replaces the standard mathematical oscillator (sine/sawtooth), while its playback speed remains strictly locked to the deterministic biometric fundamental frequency ω_bio — preserving the user's vocal timbre (formants, resonances) while pitch-shifting it to their mathematically derived cosmic frequency. The combination constitutes a "Biometric Wavetable Instrument" where the timbral identity is derived from physical voice capture and the pitch is derived from birth ephemeris.

2. The use of pairwise biometric phase resonance `k = 1/(1 + |sin(φ_i − φ_j)|)` as voice amplitude weights in real-time multi-voice additive synthesis, producing chord quality that directly encodes biometric alignment.

3. The Φ-Wave timbre formula `(sin(θ) + 0.5 × sin(θ × φ)) / 1.5` as a distinct timbral category based on the Golden Ratio harmonic, contrasted with the integer-harmonic Octave-Wave `sin(θ)`, as a biometrically-assigned timbral identity.

4. A spatial gameplay mechanic ("Chœur des Nœuds") in which participants physically reposition within a mathematically-defined geographic hexagonal cell to maximize a global harmony score H = (Σ k_ij) / N_pairs, using only acoustic feedback from the collective synthesis as guidance — no screen, no explicit coordination.

5. The coherent use of the constant F_Φ = 33.17 Hz as both (a) the wave-stretch factor in personal biometric phase computation and (b) the inter-aural frequency differential in binaural ritual entrainment, creating a single system-wide tuning constant linking spatial computation and acoustic experience.

6. Local proximity discovery via broadcast SSID packets containing personal phase φ_i, biological polarity, instrument type (synthesizer vs recorded voice), and Maya Tzolkin seal index as the sole data required for real-time collective synthesis — no network server, no user registration, no audio streaming.

7. The use of the Maya Tzolkin galactic seal color family (Red/White/Blue/Yellow, derived from `seal_index % 4`) to assign distinct musical scale systems to each voice in the collective synthesizer: Red → Harmonic Minor (6/5 interval ratios), White → Major Pentatonic (5/4, 9/8), Blue → Blues/Hexatonic (45/32, 4/3), Yellow → Lydian (3/2, 25/16). This creates a musically coherent collective chord where each participant's harmonic contribution is biographically determined by their birth date rather than explicitly chosen.

---

*This disclosure is submitted for defensive publication purposes only. The authors do not seek patent protection for the described methods and explicitly place this disclosure in the public domain of prior art.*
