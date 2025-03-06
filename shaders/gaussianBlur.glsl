//!HOOK MAIN
//!BIND HOOKED
//!SAVE PASS0
//!DESC gaussian blur pass1

vec4 hook() {
    return linearize(textureLod(HOOKED_raw, HOOKED_pos, 0.0) * HOOKED_mul);
}

//!HOOK MAIN
//!BIND PASS0
//!SAVE PASS1
//!DESC gaussian blur pass2

////////////////////////////////////////////////////////////////////////
// USER CONFIGURABLE, PASS 2 (blur in y axis)
//
// CAUTION! probably should use the same settings for "USER CONFIGURABLE, PASS 3" below
//
#define SIGMA 0.5 //blur spread or amount, (0.0, 10+]
#define RADIUS 2.0 //kernel radius (integer as float, e.g. 3.0), (0.0, 10+]
//
////////////////////////////////////////////////////////////////////////

#define get_weight(x) (exp(-(x) * (x) / (2.0 * SIGMA * SIGMA)))

vec4 hook() {
    float weight;
    vec4 csum = textureLod(PASS0_raw, PASS0_pos, 0.0) * PASS0_mul;
    float wsum = 1.0;
    for(float i = 1.0; i <= RADIUS; ++i) {
        weight = get_weight(i);
        csum += (textureLod(PASS0_raw, PASS0_pos + PASS0_pt * vec2(0.0, -i), 0.0) + textureLod(PASS0_raw, PASS0_pos + PASS0_pt * vec2(0.0, i), 0.0)) * PASS0_mul * weight;
        wsum += 2.0 * weight;
    }
    return csum / wsum;
}

//!HOOK MAIN
//!BIND PASS1
//!DESC gaussian blur pass3

////////////////////////////////////////////////////////////////////////
// USER CONFIGURABLE, PASS 3 (blur in x axis)
//
// CAUTION! probably should use the same settings for "USER CONFIGURABLE, PASS 2" above
//
#define SIGMA 1.0 //blur spread or amount, (0.0, 10+]
#define RADIUS 2.0 //kernel radius (integer as float, e.g. 3.0), (0.0, 10+]
//
////////////////////////////////////////////////////////////////////////

#define get_weight(x) (exp(-(x) * (x) / (2.0 * SIGMA * SIGMA)))

vec4 hook() {
    float weight;
    vec4 csum = textureLod(PASS1_raw, PASS1_pos, 0.0) * PASS1_mul;
    float wsum = 1.0;
    for(float i = 1.0; i <= RADIUS; ++i) {
        weight = get_weight(i);
        csum += (textureLod(PASS1_raw, PASS1_pos + PASS1_pt * vec2(-i, 0.0), 0.0) + textureLod(PASS1_raw, PASS1_pos + PASS1_pt * vec2(i, 0.0), 0.0)) * PASS1_mul * weight;
        wsum += 2.0 * weight;
    }
    return delinearize(csum / wsum);
}
