// Interféromètre cosmique ATOM4LOVE — Motif d'interférence Φ/Octave
// Affiche la superposition des ondes de deux atomes
// Singularité optique : vortex sombre central quand taux k → 1

shader_type canvas_item;

const float PHI_CONST = 1.6180340;
const float TAU_CONST = 6.2831853;

// Phases personnelles des deux atomes
uniform float phase_a : hint_range(0.0, 6.3) = 0.0;
uniform float phase_b : hint_range(0.0, 6.3) = 1.57;

// Polarité : 0 = Onde Φ (Lumière/Or), 1 = Onde Octave (Son/Bleu)
uniform int polarity_a : hint_range(0, 1) = 0;
uniform int polarity_b : hint_range(0, 1) = 1;

// Taux de résonance k ∈ [0, 1]
uniform float resonance_k : hint_range(0.0, 1.0) = 0.5;

// Constantes physiques du moteur Phi2X
uniform float f_phi : hint_range(1.0, 100.0) = 33.17;
uniform float f_two : hint_range(1.0, 100.0) = 31.32;

// Onde Φ — lumineuse, expansive, haute entropie
float wave_phi(vec2 uv, float t, float phase) {
	float r = length(uv);
	float theta = atan(uv.y, uv.x);
	// Spirale de Fibonacci modulée par f_Φ
	return sin(r * f_phi * 0.12 - t * 2.1 + phase + theta * PHI_CONST * 0.5);
}

// Onde Octave — sonore, concentrante, basse entropie
float wave_octave(vec2 uv, float t, float phase) {
	float r = length(uv);
	// Onde sphérique concentriques modulée par f_2
	return sin(r * f_two * 0.12 - t * 1.98 + phase)
	       * cos(r * 0.8 + phase * PHI_CONST * 0.3);
}

// SDF tore en 2D (section du vortex)
float sdf_vortex_ring(vec2 uv, float ring_r, float twist) {
	float angle = atan(uv.y, uv.x) + twist * length(uv);
	float r = length(uv);
	float ring = abs(r - ring_r) - 0.03;
	return ring - 0.01 * sin(angle * 7.0);
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.5;
	float t = TIME;

	// Calcul des ondes selon la polarité (sex)
	float w_a = (polarity_a == 0)
		? wave_phi(uv, t, phase_a)
		: wave_octave(uv, t, phase_a);

	float w_b = (polarity_b == 0)
		? wave_phi(uv, t, phase_b)
		: wave_octave(uv, t, phase_b);

	// Superposition : interférence constructive/destructive
	float interference = (w_a + w_b) * 0.5;
	float interference_sq = interference * interference;

	// Couleurs selon polarité
	vec3 col_phi  = vec3(1.0, 0.85, 0.1);    // Or  — Onde Φ
	vec3 col_oct  = vec3(0.1, 0.55, 1.0);    // Bleu — Onde Octave

	vec3 col_a = (polarity_a == 0) ? col_phi : col_oct;
	vec3 col_b = (polarity_b == 0) ? col_phi : col_oct;

	// Moiré d'interférence
	vec3 color = mix(col_a, col_b, 0.5 + interference * 0.5);
	color *= 0.5 + 0.7 * abs(interference);

	// --- SINGULARITÉ OPTIQUE (vortex central quand k → 1) ---
	float sing_s = smoothstep(0.80, 1.0, resonance_k);

	// Torsion du vortex animée
	float twist = sing_s * 7.0 * sin(t * 0.4);
	float vortex_r = length(uv);

	// Trou noir central — s'ouvre quand k ≈ 1 (edge0 < edge1 requis par GLSL)
	float darkness = (1.0 - smoothstep(0.0, max(0.01, 0.45 * sing_s), vortex_r)) * sing_s;
	color = mix(color, vec3(0.0), darkness);

	// Anneau lumineux (couronne)
	float ring_radius = 0.18 * sing_s + 0.02;
	float ring_sdf = sdf_vortex_ring(uv, ring_radius, twist);
	float ring_glow = exp(-abs(ring_sdf) * 18.0) * sing_s;
	color += ring_glow * mix(col_a, col_b, 0.5) * 2.5;

	// Spirales de plasma autour du vortex
	float spiral_angle = atan(uv.y, uv.x) + twist;
	float spiral = sin(spiral_angle * 5.0 - vortex_r * 10.0 + t * 1.5) * sing_s * 0.15;
	color += spiral * mix(col_a, col_b, 0.5);

	// Pulsation globale à f_Φ
	float pulse = 0.85 + 0.15 * sin(t * f_phi * 0.06 + phase_a);

	// Alpha — visible uniquement là où il y a de l'interférence
	float alpha = 0.08 + 0.55 * interference_sq + ring_glow * 0.8;
	alpha = clamp(alpha * pulse * (0.2 + 0.8 * resonance_k), 0.0, 0.92);

	COLOR = vec4(color * pulse, alpha);
}
