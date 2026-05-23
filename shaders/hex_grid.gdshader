shader_type spatial;
render_mode unshaded, blend_add, cull_disabled; // 'unshaded' pour ignorer le noir

uniform vec3 grid_color : source_color = vec3(0.0, 0.5, 1.0);
uniform float line_width : hint_range(0.01, 0.5) = 0.15; // Lignes plus épaisses
uniform float hex_size : hint_range(0.1, 10.0) = 4.0;
uniform vec3 world_offset;

float hex_distance(vec2 p) {
	p = abs(p);
	float r = 0.5 * sqrt(3.0);
	return max(p.x, p.x * 0.5 + p.y * r);
}

void fragment() {
	vec2 pos = (vec3(NODE_POSITION_WORLD.x, 0.0, NODE_POSITION_WORLD.z) + world_offset).xz;
	pos /= hex_size;
	
	vec2 r = vec2(1.0, sqrt(3.0));
	vec2 h = r * 0.5;
	vec2 a = mod(pos, r) - h;
	vec2 b = mod(pos - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	
	float d = hex_distance(g);
	// On crée une ligne bien visible
	float grid = smoothstep(0.5 - line_width, 0.5, d);
	
	ALBEDO = grid_color;
	ALPHA = grid * 0.4; // Transparence pour voir à travers
}