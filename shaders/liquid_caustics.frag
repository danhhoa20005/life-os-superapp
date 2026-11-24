#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uPrimaryColor;
uniform vec4 uAccentColor;

out vec4 fragColor;

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = pos / max(uSize, vec2(1.0));

  float t = uTime * 1.35;
  vec2 p = uv * 4.2 - vec2(2.1);

  float wave1 = sin(p.x * 1.8 + t) * cos(p.y * 1.6 - t * 0.8);
  float wave2 = sin((p.x + p.y) * 2.3 - t * 1.15) * 0.65;
  float wave3 = cos(length(p - vec2(sin(t * 0.5) * 0.6, cos(t * 0.4) * 0.5)) * 3.6 - t * 1.6);

  float caustic = clamp(0.5 + 0.28 * wave1 + 0.22 * wave2 + 0.20 * wave3, 0.0, 1.0);
  float ridge = pow(caustic, 2.4);

  vec3 base = mix(uPrimaryColor.rgb, uAccentColor.rgb, caustic);
  vec3 col = base + vec3(0.22, 0.34, 0.26) * ridge;

  float vignette = smoothstep(1.28, 0.18, length(uv - vec2(0.5)));
  float alpha = clamp(mix(0.76, 0.96, ridge) * vignette * uPrimaryColor.a, 0.0, 1.0);
  fragColor = vec4(col * alpha, alpha);
}
