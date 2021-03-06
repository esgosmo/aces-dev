// 
// Output Device Transform to an RGB computer monitor
// v0.2.1
//

//
// Summary :
//  This transform is intended for mapping OCES onto a desktop computer monitor 
//  typical of those used in motion picture visual effects production used to 
//  simulate the image appearance produced by odt_p3d60. These monitors may
//  occasionally be referred to as "sRGB" displays, however, the monitor for
//  which this transform is designed does not exactly match the specifications
//  in IEC 61966-2-1:1999.
// 
//  The assumed observer adapted white is D60, and the viewing environment is 
//  that of a dark theater. The monitor specified is intended to be more typical
//  of those found in visual effects production.
//
// Device Primaries : 
//  Primaries are those specified in Rec. ITU-R BT.709
//  CIE 1931 chromaticities:  x         y         Y
//              Red:          0.64      0.33
//              Green:        0.3       0.6
//              Blue:         0.15      0.06
//              White:        0.3217    0.329     100 cd/m^2
//
// Display EOTF :
//  The reference electro-optical transfer function specified in 
//  IEC 61966-2-1:1999.
//
// Assumed observer adapted white point:
//         CIE 1931 chromaticities:    x            y
//                                     0.32168      0.33767
//
// Viewing Environment:
//  Environment specified in SMPTE RP 431-2-2007
//   Note: This environment is consistent with the viewing environment typical
//     of a motion picture theater. This ODT makes no attempt to compensate for 
//     viewing environment variables more typical of those associated with the 
//     home.
//

import "utilities";
import "utilities-aces";

/* ----- ODT Parameters ------ */
const Chromaticities DISPLAY_PRI = REC709_PRI;
const float OCES_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(ACES_PRI,1.0);
const float XYZ_2_DISPLAY_PRI_MAT[4][4] = XYZtoRGB(DISPLAY_PRI,1.0);

const Chromaticities RENDERING_PRI = 
{
  {0.73470, 0.26530},
  {0.00000, 1.00000},
  {0.12676, 0.03521},
  {0.32168, 0.33767}
};
const float XYZ_2_RENDERING_PRI_MAT[4][4] = XYZtoRGB(RENDERING_PRI,1.0);
const float OCES_PRI_2_RENDERING_PRI_MAT[4][4] = mult_f44_f44( OCES_PRI_2_XYZ_MAT, XYZ_2_RENDERING_PRI_MAT);

// ODT parameters related to black point compensation (BPC) and encoding
const float ODT_OCES_BP = 0.0016;
const float ODT_OCES_WP = 48.0;
const float OUT_BP = 0.01;
const float OUT_WP = 100.0;

const unsigned int BITDEPTH = 8;
const unsigned int CV_BLACK = 0;
const unsigned int CV_WHITE = pow( 2, BITDEPTH) - 1;

// Derived BPC and scale parameters
const float BPC = (ODT_OCES_BP * OUT_WP - ODT_OCES_WP * OUT_BP) / 
                  (ODT_OCES_BP - ODT_OCES_WP);
const float SCALE = (OUT_BP - OUT_WP) / (ODT_OCES_BP - ODT_OCES_WP);


void main 
(
  input varying float rIn, 
  input varying float gIn, 
  input varying float bIn, 
  input varying float aIn,
  output varying float rOut,
  output varying float gOut,
  output varying float bOut,
  output varying float aOut
)
{
  // Put input variables (OCES) into a 3-element vector
  float oces[3] = {rIn, gIn, bIn};

  /*--- Tone Scale ---*/
    // Convert from OCES to rendering primaries encoding
    float rgbPre[3] = mult_f3_f44( oces, OCES_PRI_2_RENDERING_PRI_MAT);

    // Apply the ODT tone scale independently to RGB 
    float rgbPost[3];
    rgbPost[0] = odt_tonescale_fwd( rgbPre[0]);
    rgbPost[1] = odt_tonescale_fwd( rgbPre[1]);
    rgbPost[2] = odt_tonescale_fwd( rgbPre[2]);

    // Restore the hue to the pre-tonescale value
    float rgbRestored[3] = restore_hue_dw3( rgbPre, rgbPost);

    // Convert rendering primaries back to OCES encoding
    rgbRestored = mult_f3_f44( rgbRestored, invert_f44( OCES_PRI_2_RENDERING_PRI_MAT));

  // Translate rendered RGB to CIE XYZ
  float XYZ[3] = mult_f3_f44( rgbRestored, OCES_PRI_2_XYZ_MAT);

  // CIE XYZ to display primaries
  float rgbOut[3] = mult_f3_f44( XYZ, XYZ_2_DISPLAY_PRI_MAT);

  // Clip negative values (i.e. outside the display primaries)
  float rgbOutClamp[3] = clamp_f3( rgbOut, 0., HALF_POS_INF);    
  
  // Restore hue after clip operation ("smart-clip")
  rgbOut = restore_hue_dw3( rgbOut, rgbOutClamp);

  // Black Point Compensation
  float offset_scaled[3];
  offset_scaled[0] = (SCALE * rgbOut[0]) + BPC;
  offset_scaled[1] = (SCALE * rgbOut[1]) + BPC;
  offset_scaled[2] = (SCALE * rgbOut[2]) + BPC;    

  // CCTF
  float tmp[3];
  tmp[0] = max( (offset_scaled[0] - OUT_BP)/(OUT_WP - OUT_BP), 0.);
  tmp[1] = max( (offset_scaled[1] - OUT_BP)/(OUT_WP - OUT_BP), 0.);
  tmp[2] = max( (offset_scaled[2] - OUT_BP)/(OUT_WP - OUT_BP), 0.);

  float cctf[3];
  // moncurve_r with gamma of 2.4 and offset of 0.055 matches the EOTF found in IEC 61966-2-1:1999 (sRGB)
  cctf[0] = CV_BLACK + (CV_WHITE - CV_BLACK) * moncurve_r( tmp[0], 2.4, 0.055);
  cctf[1] = CV_BLACK + (CV_WHITE - CV_BLACK) * moncurve_r( tmp[1], 2.4, 0.055);
  cctf[2] = CV_BLACK + (CV_WHITE - CV_BLACK) * moncurve_r( tmp[2], 2.4, 0.055);

  float outputCV[3] = clamp_f3( cctf, 0., pow( 2, BITDEPTH)-1);

  // This step converts integer CV back into 0-1 which is what CTL expects
  outputCV = mult_f_f3( 1./(pow(2,BITDEPTH)-1), outputCV);

  /*--- Cast outputCV to rOut, gOut, bOut ---*/
  rOut = outputCV[0];
  gOut = outputCV[1];
  bOut = outputCV[2];
  aOut = aIn;
}