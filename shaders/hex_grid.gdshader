// Horizon Fil de Fer — hex grid néon style Tron/Blade Runner
// Effet : lignes fines à l'horizon, épaisses au premier plan, lueur néon, fondu de distance
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

const float SQRT3     = 1.7320508;
const float SQRT3_INV = 0.5773503;

uniform vec3  grid_color      : source_color = vec3(0.0, 0.65, 1.0);
uniform vec3  horizon_color   : source_color = vec3(0.3, 0.0, 1.0); // violet horizon
uniform float line_width      : hint_range(0.01, 0.4) = 0.10;
uniform float hex_size        : hint_range(0.1, 10.0) = 4.0;
uniform vec3  world_offset;
uniform float pulse_speed     = 1.0;
uniform vec3  camera_pos;      // position caméra en espace monde (mis à jour chaque frame)

// Lignes de Planck (vers les pentagones)
uniform vec3  pentagon_near1  = vec3(0.0,  0.0, 99999.0);
uniform vec3  pentagon_near2  = vec3(99999.0, 0.0, 0.0);
uniform float planck_intensity : hint_range(0.0, 1.0) = 0.40;

// Distances pour le fondu horizon fil de fer
uniform float fade_near : hint_range(1.0, 50.0)  = 8.0;
uniform float fade_far  : hint_range(10.0, 500.0) = 90.0;
// Rituel de Phase : glow progressif (0.0 → 5.0 sur 33 secondes)
uniform float glow_intensity : hint_range(0.0, 5.0) = 0.0;

varying vec3 v_world_pos;

float hex_distance(vec2 p) {
	p = abs(p);
	return max(p.x, p.x * 0.5 + p.y * SQRT3 * 0.5);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_pos = (v_world_pos + world_offset).xz;
	vec2 pos = world_pos / hex_size;

	// ── Distance calculée en fragment : PlaneMesh n'a que 4 sommets, l'interpolation
	// vertex serait inexacte (centre du mesh = distance 141 au lieu de 0)
	float dist = length(world_pos - camera_pos.xz);
	float horizon_fade = 1.0 - smoothstep(fade_near, fade_far, dist);
	if (horizon_fade <= 0.001) discard;

	// ── Largeur de ligne adaptive ──
	float lw_near = line_width * 1.6;
	float lw_far  = line_width * 0.25;
	float lw = mix(lw_far, lw_near, smoothstep(fade_near * 0.5, fade_near * 0.1, dist));

	// ── Grille hexagonale (flat-top offset) ──
	vec2 r = vec2(1.0, SQRT3);
	vec2 h = r * 0.5;
	vec2 a = mod(pos, r) - h;
	vec2 b = mod(pos - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;

	float d = hex_distance(g);
	// Ligne nette (arête) + halo de lueur néon (glow)
	float edge  = smoothstep(0.5 - lw,           0.5,           d);  // arête vive
	float glow  = smoothstep(0.5 - lw * 3.5,     0.5 - lw,      d) * 0.35;  // halo doux

	// ── Lignes de Planck (vers pentagones) ──
	vec2 d1 = pentagon_near1.xz - world_pos;
	vec2 d2 = pentagon_near2.xz - world_pos;
	vec2 to_p1  = length(d1) > 0.001 ? normalize(d1) : vec2(1.0, 0.0);
	vec2 to_p2  = length(d2) > 0.001 ? normalize(d2) : vec2(0.0, 1.0);
	vec2 g_dir  = length(g)  > 0.001 ? normalize(g)  : vec2(1.0, 0.0);
	float align1 = abs(dot(g_dir, to_p1));
	float align2 = abs(dot(g_dir, to_p2));
	float planck = max(smoothstep(0.82, 0.99, align1),
	                   smoothstep(0.82, 0.99, align2)) * planck_intensity;

	// ── Pulsation radiale (onde sortant du joueur) ──
	float pulse = 0.5 + 0.5 * sin(length(pos) * 0.35 - TIME * pulse_speed * 0.5);

	// ── Couleur : bleu électrique au premier plan → violet à l'horizon ──
	vec3 base_color = mix(grid_color, horizon_color, 1.0 - horizon_fade);
	vec3 planck_col = vec3(1.0, 0.88, 0.1);  // or chaud pour les Lignes de Planck
	vec3 color      = mix(base_color, planck_col, clamp(planck, 0.0, 1.0));

	// ── Alpha final ──
	float alpha = (edge + glow) * horizon_fade * (0.4 + pulse * 0.12)
	            + planck * 0.35 * horizon_fade;

	// ── Rituel : halo blanc pulsant autour des arêtes ──────────────────────────
	float ritual_glow_factor = glow_intensity * 0.2;  // 0→1 sur la plage 0→5
	vec3 ritual_white = vec3(1.0, 1.0, 1.0);
	color = mix(color, ritual_white, clamp(ritual_glow_factor * edge, 0.0, 0.6));
	alpha += edge * ritual_glow_factor * horizon_fade;

	ALBEDO = color;
	EMISSION = color * (edge * (0.6 + glow_intensity * 0.3) + planck * 0.8);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
