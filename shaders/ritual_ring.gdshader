// Anneau radial de progression du Rituel de Phase (33 secondes)
// pct : 0.0 → 1.0 (temps écoulé / 33s)
shader_type canvas_item;

uniform float pct : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_start : source_color = vec4(0.0, 0.8, 1.0, 1.0);  // cyan
uniform vec4 color_end   : source_color = vec4(1.0, 0.85, 0.1, 1.0); // or (singularité)

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;  // [-1, 1]
    float r = length(uv);

    // Anneau entre 0.7 et 0.95 (rayon normalisé)
    float ring_inner = 0.70;
    float ring_outer = 0.92;
    float in_ring = smoothstep(ring_inner - 0.03, ring_inner, r) *
                    (1.0 - smoothstep(ring_outer, ring_outer + 0.03, r));

    // Angle [0, 2π] depuis le haut (-π/2), sens horaire
    float angle = atan(uv.x, -uv.y);  // [-π, π]
    if (angle < 0.0) angle += 6.28318;  // [0, 2π]

    // Arc rempli de 0 → pct * 2π
    float arc_end = pct * 6.28318;
    float in_arc  = step(angle, arc_end);

    // Tête de l'arc (glow point)
    float head_angle = arc_end;
    float head_dist  = abs(angle - head_angle);
    float head_glow  = smoothstep(0.3, 0.0, head_dist) * 0.8;

    // Couleur : gradient cyan → or à mesure que pct → 1
    vec4 col = mix(color_start, color_end, pct);

    // Pulsation légère en fin de rituel
    float pulse = 1.0 + sin(TIME * 6.28 * 4.0) * 0.12 * smoothstep(0.7, 1.0, pct);

    float alpha = in_ring * (in_arc * 0.8 + head_glow) * pulse;
    // Fond gris très transparent pour voir le contour complet
    float bg = in_ring * 0.08;

    COLOR = col * alpha + vec4(1.0,1.0,1.0, bg);
    COLOR.a = max(alpha, bg);
}
