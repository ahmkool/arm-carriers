shader_type spatial;

// Castle stone for pieces that drop into a bottomless black chasm (the castle siege's wall, towers and bridge piers).
// Same as castle_stone.gdshader, but it applies the fog itself and fades it out along with the stone (fade_depth),
// so the bottom of the stone is exactly as black as the unfogged chasm floor. Environment fog would tint it.
#define CHASM_FOG
#include "res://src/world/elements/medieval/castle_stone.gdshaderinc"
