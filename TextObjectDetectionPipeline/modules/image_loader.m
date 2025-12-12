function [image, imageInfo] = image_loader(imagePath, config)
%IMAGE_LOADER Load and validate an image file
%
%   [IMAGE, IMAGEINFO] = IMAGE_LOADER(IMAGEPATH, CONFIG) loads an image
%   from the specified path and validates it against supported formats.
%
%   Inputs:
%       imagePath - Full path to the image file
%       config    - Configuration structure from default_config()
%
%   Outputs:
%       image     - Loaded image matrix (RGB or grayscale)
%       imageInfo - Structure containing image metadata:
%                   .width, .height, .channels, .format, .fileSize
%
%   Errors:
%       Throws error if file doesn't exist, format unsupported, or image corrupt
%
%   Example:
%       config = default_config();
%       [img, info] = image_loader('test.png', config);
%
%   See also: IMREAD, IMFINFO, DEFAULT_CONFIG

    %% Input Validation
    if nargin < 2
        error('IMAGE_LOADER:InvalidInput', 'Both imagePath and config are required.');
    end
    
    if ~ischar(imagePath) && ~isstring(imagePath)
        error('IMAGE_LOADER:InvalidInput', 'imagePath must be a string or character array.');
    end
    
    imagePath = char(imagePath);  % Ensure char array
    
    %% Check File Existence
    if ~isfile(imagePath)
        error('IMAGE_LOADER:FileNotFound', 'Image file not found: %s', imagePath);
    end
    
    %% Validate File Format
    [~, fileName, fileExt] = fileparts(imagePath);
    fileExt = lower(fileExt);
    
    if ~ismember(fileExt, config.supportedFormats)
        error('IMAGE_LOADER:UnsupportedFormat', ...
            'Unsupported image format: %s\nSupported formats: %s', ...
            fileExt, strjoin(config.supportedFormats, ', '));
    end
    
    %% Get File Information
    try
        fileInfo = dir(imagePath);
        fileSizeBytes = fileInfo.bytes;
    catch
        fileSizeBytes = 0;
    end
    
    %% Load Image
    try
        % Get image info without loading
        imgInfo = imfinfo(imagePath);
        
        % Load the image
        image = imread(imagePath);
        
        % Handle indexed images (convert to RGB)
        if isfield(imgInfo, 'ColorType') && strcmp(imgInfo.ColorType, 'indexed')
            [image, ~] = imread(imagePath);
            if size(image, 3) == 1
                % Convert indexed to RGB using colormap
                [image, cmap] = imread(imagePath);
                image = ind2rgb(image, cmap);
                image = uint8(image * 255);
            end
        end
        
    catch ME
        error('IMAGE_LOADER:ReadError', ...
            'Failed to read image file: %s\nError: %s', imagePath, ME.message);
    end
    
    %% Validate Image Data
    if isempty(image)
        error('IMAGE_LOADER:EmptyImage', 'Loaded image is empty: %s', imagePath);
    end
    
    [height, width, channels] = size(image);
    
    if height < 10 || width < 10
        error('IMAGE_LOADER:ImageTooSmall', ...
            'Image too small for processing: %dx%d pixels', width, height);
    end
    
    %% Convert to uint8 if necessary
    if isa(image, 'uint16')
        image = im2uint8(image);
    elseif isa(image, 'double')
        if max(image(:)) <= 1
            image = im2uint8(image);
        else
            image = uint8(image);
        end
    elseif isa(image, 'single')
        if max(image(:)) <= 1
            image = im2uint8(image);
        else
            image = uint8(image);
        end
    elseif isa(image, 'logical')
        image = im2uint8(image);
    end
    
    %% Ensure RGB for color images
    if channels == 4
        % RGBA - remove alpha channel
        image = image(:,:,1:3);
        channels = 3;
    elseif channels == 1
        % Grayscale - keep as is for now
        % Will be converted to RGB if needed elsewhere
    end
    
    %% Build Image Info Structure
    imageInfo = struct();
    imageInfo.width = width;
    imageInfo.height = height;
    imageInfo.channels = channels;
    imageInfo.format = fileExt;
    imageInfo.fileName = fileName;
    imageInfo.filePath = imagePath;
    imageInfo.fileSize = fileSizeBytes;
    imageInfo.bitDepth = imgInfo(1).BitDepth;
    imageInfo.colorType = imgInfo(1).ColorType;
    
    % Add image dimensions string for display
    imageInfo.dimensionsStr = sprintf('%dx%dx%d', width, height, channels);
    
    if config.processing.verbose
        fprintf('[IMAGE_LOADER] Successfully loaded: %s (%s)\n', ...
            fileName, imageInfo.dimensionsStr);
    end

end
