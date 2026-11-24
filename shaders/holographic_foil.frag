#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uPointer;
uniform vec4 uBaseColor;
uniform vec4 uSheenColor;

out vec4 fragColor;

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = pos / max(uSize, vec2(1.0));

  vec2 ptr = clamp(uPointer, vec2(0.0), vec2(1.0));
  vec2 delta = uv - ptr;
  float dist = length(delta);

  float angleBand = (uv.x * 0.82 + uv.y * 0.58) - (ptr.x - 0.5) * 0.75 + sin(uTime * 0.9) * 0.08;
  float foilSweep = exp(-pow((angleBand - 0.68) * 5.2, 2.0));
  float spotGlow = exp(-dist * 3.4) * 0.45;

  vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (angleBand * 1.4 + vec3(0.0, 0.28, 0.56)) + uTime * 0.6);
  vec3 sheen = mix(uSheenColor.rgb, rainbow, 0.32) * (foilSweep * 0.78 + spotGlow);

  vec3 col = clamp(uBaseColor.rgb + sheen, 0.0, 1.0);
  float alpha = clamp(uBaseColor.a, 0.0, 1.0);
  fragColor = vec4(col * alpha, alpha);
}
