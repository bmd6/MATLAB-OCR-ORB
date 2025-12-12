# Text and Object Detection Pipeline

## Overview

A modular MATLAB R2024b pipeline for text identification/extraction (using OCR Tesseract) and object detection/extraction (using ORB feature matching).

**Version:** 1.0.0  
**MATLAB Version:** R2024b  
**Required Toolboxes:** Computer Vision Toolbox, Image Processing Toolbox

## Features

- **Text Detection (OCR)**
  - Tesseract-based optical character recognition
  - Configurable confidence threshold (default: 80%)
  - Reference text matching with Levenshtein distance
  - Word-level bounding boxes

- **Object Detection (ORB)**
  - ORB (Oriented FAST and Rotated BRIEF) feature detection
  - Multi-scale detection (configurable scales)
  - RANSAC-based geometric verification
  - Multiple instance detection (up to 8 per reference)
  - Non-maximum suppression for overlapping detections
  - Color extraction from detected regions

- **Preprocessing**
  - Adaptive histogram equalization (CLAHE)
  - Gaussian/median denoising
  - Optional sharpening
  - Automatic resizing for large images

- **Visualization**
  - Green bounding boxes for text
  - Blue bounding boxes for objects
  - Confidence labels
  - Color crop display for detected objects

## Directory Structure

```
TextObjectDetectionPipeline/
├── main_pipeline.m              # Main entry point
├── config/
│   └── default_config.m         # Configuration parameters
├── modules/
│   ├── image_loader.m           # Image loading & validation
│   ├── load_reference_data.m    # Reference data loading
│   ├── preprocessor.m           # Image enhancement
│   ├── text_detector.m          # OCR/Tesseract detection
│   ├── object_detector.m        # ORB-based detection
│   ├── accuracy_calculator.m    # Metrics computation
│   ├── visualizer.m             # Results visualization
│   └── process_frame.m          # Single frame processor (for video)
├── utils/
│   ├── validate_inputs.m        # Input validation
│   └── feature_cache.m          # Feature caching utility
├── example_data/
│   └── reference_text.txt       # Example reference text file
└── README.md                    # This file
```

## Quick Start

1. Open MATLAB R2024b
2. Navigate to the `TextObjectDetectionPipeline` directory
3. Run `main_pipeline.m`
4. Follow the prompts to select:
   - Input image
   - Reference images directory

## Reference Text File Format

The reference text file (`reference_text.txt`) should be placed in the reference images directory.

**Format:** Plain text file with one expected text string per line.

**Example (`reference_text.txt`):**
```
STOP
EXIT
WARNING
DANGER
Serial: 12345
Model ABC-123
Part No: 7890
```

## Configuration

Edit `config/default_config.m` to customize parameters:

### OCR Settings
```matlab
config.ocr.confidenceThreshold = 80;  % Minimum confidence (0-100)
config.ocr.language = 'English';       % OCR language
config.ocr.layoutAnalysis = 'Block';   % 'Auto', 'Block', 'Line', 'Word'
```

### ORB Settings
```matlab
config.orb.minMatchedFeatures = 10;    % Minimum matches for detection
config.orb.matchRatioThreshold = 0.75; % Lowe's ratio test threshold
config.orb.maxInstancesPerReference = 8; % Max instances per reference
config.orb.minInlierRatio = 0.50;      % Minimum RANSAC inlier ratio
```

### Preprocessing
```matlab
config.preprocessing.enabled = true;
config.preprocessing.contrastEnhancement.enabled = true;
config.preprocessing.denoising.enabled = true;
config.preprocessing.resize.maxDimension = 2000;
```

### Visualization
```matlab
config.visualization.textBoxColor = [0, 255, 0];    % Green
config.visualization.objectBoxColor = [0, 0, 255];  % Blue
config.visualization.showConfidence = true;
config.visualization.showLabels = true;
```

## Region of Interest (ROI)

You can optionally specify a region of interest to focus detection:

When prompted, enter coordinates:
- X: top-left corner X coordinate
- Y: top-left corner Y coordinate
- Width: ROI width in pixels
- Height: ROI height in pixels

## Accuracy Metrics

### Text Detection
- **Average Confidence:** Mean OCR confidence of detected text
- **Reference Match Rate:** Percentage of reference texts found
- **Similarity Score:** Levenshtein similarity to reference text

### Object Detection
- **Feature Match Ratio:** Matched features / total reference features
- **Inlier Ratio:** RANSAC inliers / total matches
- **Geometric Consistency:** Combined weighted score

## Output

### Terminal Output
Detailed results are printed to the MATLAB command window including:
- Each detected text with confidence and bounding box
- Each detected object instance with metrics
- Color information for detected objects
- Processing time breakdown

### Visualization
A figure window displays:
- Input image with annotated bounding boxes
- Color crops of detected objects
- Summary statistics

### Workspace Variable
Results are saved to `pipelineResults` in the MATLAB workspace.

## Supported Image Formats

- PNG (`.png`)
- JPEG (`.jpg`, `.jpeg`)
- BMP (`.bmp`)
- TIFF (`.tiff`, `.tif`)
- GIF (`.gif`)

## Future Enhancements (Planned)

- **Video Processing:** Use `process_frame.m` for video input
- **Parallel Processing:** Enable for multiple reference images
- **Report Generation:** Export results to PDF/HTML
- **GUI Interface:** Interactive parameter adjustment

## Video Processing (Future)

The `process_frame.m` function is designed for video integration:

```matlab
% Example video processing (future implementation)
config = default_config();
[refImages, refText, ~] = load_reference_data('./refs', config);

vidReader = VideoReader('input_video.mp4');
frameNum = 0;

while hasFrame(vidReader)
    frame = readFrame(vidReader);
    frameNum = frameNum + 1;
    
    % Process every Nth frame for efficiency
    if mod(frameNum, 5) == 0
        results = process_frame(frame, refImages, refText, config);
        % Handle results...
    end
end
```

## Troubleshooting

### "No text detected"
- Check image quality and contrast
- Try adjusting `config.ocr.confidenceThreshold`
- Ensure text is clear and not too small

### "No objects detected"
- Verify reference images contain distinctive features
- Increase `config.orb.maxFeatures`
- Decrease `config.orb.minMatchedFeatures`
- Check that reference objects are actually in the image

### "OCR failed"
- Ensure Computer Vision Toolbox is installed
- Check that OCR language is installed
- Verify image format is supported

### Performance Issues
- Enable `config.preprocessing.resize.enabled`
- Reduce `config.orb.maxFeatures`
- Disable multi-scale detection

## License

This pipeline is provided as-is for educational and research purposes.

## Contact

For issues or suggestions, please refer to the documentation or modify the configuration as needed.
