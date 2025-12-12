function config = default_config()
%DEFAULT_CONFIG Returns the default configuration structure for the pipeline
%
%   config = DEFAULT_CONFIG() returns a structure containing all
%   configurable parameters for the text and object detection pipeline.
%
%   Configuration Sections:
%       - ocr: OCR/Tesseract settings
%       - orb: ORB feature detection settings
%       - preprocessing: Image enhancement settings
%       - visualization: Display and color settings
%       - processing: General processing parameters
%
%   To customize, either modify this file or create a copy and load it
%   in the main pipeline script.
%
%   Example:
%       config = default_config();
%       config.ocr.confidenceThreshold = 90;  % Increase threshold
%
%   See also: MAIN_PIPELINE

%% OCR (Tesseract) Configuration
config.ocr = struct();

% Minimum confidence threshold for text detection (0-100)
% Text with confidence below this threshold will not be reported
config.ocr.confidenceThreshold = 80;

% Supported language for OCR
config.ocr.language = 'English';

% Character whitelist (empty = all characters)
% Example: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
config.ocr.characterSet = '';

% Layout analysis mode for OCR
% Options: 'Auto', 'Block', 'Line', 'Word', 'Character'
config.ocr.layoutAnalysis = 'Block';

% Text polarity: 'DarkTextOnLight', 'LightTextOnDark', 'Auto'
config.ocr.textPolarity = 'Auto';

%% ORB Feature Detection Configuration
config.orb = struct();

% Minimum number of matched features required for a valid match
config.orb.minMatchedFeatures = 10;

% Match ratio threshold (Lowe's ratio test)
% Lower values = stricter matching
config.orb.matchRatioThreshold = 0.75;

% Maximum number of features to detect per image
config.orb.maxFeatures = 1000;

% RANSAC parameters for geometric verification
config.orb.ransac.enabled = true;
config.orb.ransac.threshold = 3.0;  % Reprojection error threshold in pixels
config.orb.ransac.confidence = 0.99;
config.orb.ransac.maxIterations = 2000;

% Minimum RANSAC inlier ratio for valid detection
config.orb.minInlierRatio = 0.50;

% Maximum instances of the same object to detect
config.orb.maxInstancesPerReference = 8;

% Multi-scale detection settings
config.orb.multiScale.enabled = true;
config.orb.multiScale.scales = [0.5, 0.75, 1.0, 1.25, 1.5];

% Non-maximum suppression overlap threshold for multiple detections
config.orb.nmsOverlapThreshold = 0.5;

%% Preprocessing Configuration
config.preprocessing = struct();

% Enable/disable preprocessing enhancement
config.preprocessing.enabled = true;

% Contrast adjustment using adaptive histogram equalization
config.preprocessing.contrastEnhancement.enabled = true;
config.preprocessing.contrastEnhancement.clipLimit = 0.02;
config.preprocessing.contrastEnhancement.numTiles = [8, 8];

% Denoising using non-local means or Gaussian filter
config.preprocessing.denoising.enabled = true;
config.preprocessing.denoising.method = 'gaussian';  % 'gaussian' or 'median'
config.preprocessing.denoising.filterSize = 3;

% Sharpening
config.preprocessing.sharpening.enabled = false;
config.preprocessing.sharpening.amount = 0.5;  % 0-1

% Resize large images for faster processing
config.preprocessing.resize.enabled = true;
config.preprocessing.resize.maxDimension = 2000;  % Max width or height in pixels

% Grayscale conversion for feature detection
config.preprocessing.convertToGray = true;

%% Visualization Configuration
config.visualization = struct();

% Bounding box colors (RGB, 0-255)
config.visualization.textBoxColor = [0, 255, 0];    % Green for text
config.visualization.objectBoxColor = [0, 0, 255];  % Blue for objects

% Bounding box line width
config.visualization.lineWidth = 2;

% Font size for labels
config.visualization.fontSize = 12;

% Show confidence scores on visualization
config.visualization.showConfidence = true;

% Show labels on bounding boxes
config.visualization.showLabels = true;

% Figure size [width, height] in pixels
config.visualization.figureSize = [1200, 800];

%% Processing Configuration
config.processing = struct();

% Enable parallel processing for multiple reference images
config.processing.useParallel = true;

% Number of workers for parallel pool (0 = auto)
config.processing.numWorkers = 0;

% Cache reference image features
config.processing.cacheFeatures = true;

% Verbose output during processing
config.processing.verbose = true;

% Processing mode: 'sequential' or 'parallel'
% Note: Within-frame is sequential (text then objects)
% Parallel is used for multiple reference image matching
config.processing.mode = 'sequential';

%% Supported Image Formats
config.supportedFormats = {'.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.tif', '.gif'};

%% Reference Text File Settings
config.referenceText.fileName = 'reference_text.txt';
config.referenceText.encoding = 'UTF-8';

%% Accuracy Calculation Weights
config.accuracy = struct();
config.accuracy.textWeight = 0.5;      % Weight for text detection in overall accuracy
config.accuracy.objectWeight = 0.5;    % Weight for object detection in overall accuracy

% Levenshtein distance threshold for text matching (0-1, ratio of string length)
config.accuracy.textMatchThreshold = 0.8;

%% Region Exclusion Settings
config.exclusion = struct();

% Padding around detected regions when excluding (pixels)
config.exclusion.padding = 5;

% Minimum overlap ratio to consider region as excluded
config.exclusion.overlapThreshold = 0.3;

end
