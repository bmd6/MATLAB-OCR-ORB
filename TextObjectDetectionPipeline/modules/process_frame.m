function frameResults = process_frame(frame, referenceImages, referenceText, config, roi, useROI)
%PROCESS_FRAME Process a single frame for text and object detection
%
%   FRAMERESULTS = PROCESS_FRAME(FRAME, REFERENCEIMAGES, REFERENCETEXT, CONFIG, ROI, USEROI)
%   processes a single frame/image through the complete detection pipeline.
%
%   This function is designed for easy integration with video processing loops.
%   It performs all detection steps on a single frame and returns structured results.
%
%   Inputs:
%       frame           - Input frame (RGB or grayscale image)
%       referenceImages - Structure array of reference images (pre-loaded)
%       referenceText   - Cell array of expected text strings
%       config          - Configuration structure from default_config()
%       roi             - Region of interest [x, y, width, height] (optional)
%       useROI          - Boolean flag indicating ROI usage (optional)
%
%   Outputs:
%       frameResults - Structure containing:
%                      .textDetections   - Text detection results
%                      .objectDetections - Object detection results
%                      .textRegions      - Binary mask of text regions
%                      .objectRegions    - Binary mask of object regions
%                      .excludedRegions  - Regions excluded from detection
%                      .processingTime   - Processing time in seconds
%                      .success          - Boolean indicating success
%                      .errorMessage     - Error message if failed
%
%   Example:
%       % For single image
%       config = default_config();
%       [refImages, refText, ~] = load_reference_data('./refs', config);
%       results = process_frame(img, refImages, refText, config);
%
%       % For video processing (future use)
%       vidReader = VideoReader('video.mp4');
%       while hasFrame(vidReader)
%           frame = readFrame(vidReader);
%           results = process_frame(frame, refImages, refText, config);
%           % Process results...
%       end
%
%   See also: TEXT_DETECTOR, OBJECT_DETECTOR, PREPROCESSOR

    %% Initialize Output
    frameResults = struct();
    frameResults.textDetections = struct('text', {}, 'confidence', {}, 'boundingBox', {});
    frameResults.objectDetections = struct('referenceName', {}, 'instances', {});
    frameResults.textRegions = [];
    frameResults.objectRegions = [];
    frameResults.excludedRegions = [];
    frameResults.processingTime = 0;
    frameResults.success = false;
    frameResults.errorMessage = '';
    
    %% Input Validation
    if nargin < 4
        frameResults.errorMessage = 'Insufficient inputs. Need frame, referenceImages, referenceText, and config.';
        return;
    end
    
    if nargin < 5 || isempty(roi)
        roi = [];
    end
    
    if nargin < 6
        useROI = false;
    end
    
    if isempty(frame)
        frameResults.errorMessage = 'Input frame is empty.';
        return;
    end
    
    %% Start Timer
    tic;
    
    %% Store Original Frame
    originalFrame = frame;
    
    %% Preprocessing
    try
        [processedFrame, ~] = preprocessor(frame, config, roi, useROI);
    catch ME
        frameResults.errorMessage = sprintf('Preprocessing failed: %s', ME.message);
        frameResults.processingTime = toc;
        return;
    end
    
    %% Text Detection (OCR)
    try
        [textDetections, textRegions] = text_detector(processedFrame, originalFrame, ...
            referenceText, config, roi, useROI);
        frameResults.textDetections = textDetections;
        frameResults.textRegions = textRegions;
    catch ME
        % Text detection failed but continue with object detection
        if config.processing.verbose
            warning('PROCESS_FRAME:TextError', 'Text detection failed: %s', ME.message);
        end
    end
    
    %% Build Excluded Regions (text regions to exclude from object detection)
    excludedRegions = [];
    if ~isempty(frameResults.textDetections)
        for i = 1:length(frameResults.textDetections)
            if frameResults.textDetections(i).confidence >= config.ocr.confidenceThreshold
                excludedRegions = [excludedRegions; frameResults.textDetections(i).boundingBox];
            end
        end
    end
    frameResults.excludedRegions = excludedRegions;
    
    %% Object Detection (ORB)
    try
        [objectDetections, objectRegions] = object_detector(processedFrame, originalFrame, ...
            referenceImages, config, excludedRegions, roi, useROI);
        frameResults.objectDetections = objectDetections;
        frameResults.objectRegions = objectRegions;
    catch ME
        % Object detection failed
        if config.processing.verbose
            warning('PROCESS_FRAME:ObjectError', 'Object detection failed: %s', ME.message);
        end
    end
    
    %% Finalize
    frameResults.processingTime = toc;
    frameResults.success = true;

end
