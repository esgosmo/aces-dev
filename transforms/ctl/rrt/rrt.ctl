// 
// Reference Rendering Transform (RRT)
// v0.2.1
//

import "utilities";
import "utilities-aces";

const Chromaticities RENDERING_PRI = 
{
  {0.73470, 0.26530},
  {0.00000, 1.00000},
  {0.12676, 0.03521},
  {0.32168, 0.33767}
};

const float ACES_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(ACES_PRI,1.0);
const float XYZ_2_RENDERING_PRI_MAT[4][4] = XYZtoRGB(RENDERING_PRI,1.0);
const float ACES_PRI_2_RENDERING_PRI_MAT[4][4] = mult_f44_f44( ACES_PRI_2_XYZ_MAT, XYZ_2_RENDERING_PRI_MAT);

// Chroma scaling parameters
const float center = 350.;    // center hue (in degrees)
const float width = 140.;     // full base width (in degrees)
const float percent = 0.83;   // percent scale (0-1)
        
// Reference Rendering Transform (RRT)
//   Input is ACES RGB (linearly encoded)
//   Output is OCES RGB (linearly encoded)
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
  // Put input variables into a 3-element array (ACES)
  float aces[3] = {rIn, gIn, bIn};

  // Adjust ACES values
  float yab[3] = rgb_2_yab( aces);

    // Scale chroma in red/magenta region
    yab = scale_C_at_H( yab, center, width, percent);  

  aces = yab_2_rgb( yab);
  
  // Convert from ACES RGB encoding to rendering primaries RGB encoding
  float oces[3];
  if (yab[0] > 0.0) { // temp. hack to avoid issue that can occur when (Y < 0)
    float rgbPre[3] = mult_f3_f44( aces, ACES_PRI_2_RENDERING_PRI_MAT);

      // Apply the RRT tone scale independently to RGB
      float rgbPost[3];
      rgbPost[0] = rrt_tonescale_fwd( rgbPre[0]);
      rgbPost[1] = rrt_tonescale_fwd( rgbPre[1]);
      rgbPost[2] = rrt_tonescale_fwd( rgbPre[2]);

    // Restore the hue to the pre-tonescale hue
    float rgbRestored[3] = restore_hue_dw3( rgbPre, rgbPost);

    // Convert from rendering primaries RGB encoding to OCES RGB encoding
    oces = mult_f3_f44( rgbRestored, invert_f44(ACES_PRI_2_RENDERING_PRI_MAT));
  } else {
    oces[0] = 0.0001;     
    oces[1] = 0.0001;    
    oces[2] = 0.0001;
  }
    
  // Assign OCES-RGB to output variables (OCES)
  rOut = oces[0];
  gOut = oces[1];
  bOut = oces[2];
  aOut = aIn;
}