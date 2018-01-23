function [dut_out,dut_in,t,dut_out_unit,dut_in_unit,X0_RMS] = mataa_measure_signal_response (X0,fs,latency,verbose,channels,cal);

% function [dut_out,dut_in,t,dut_out_unit,dut_in_unit] = mataa_measure_signal_response (X0,fs,latency,verbose,channels,cal);
%
% DESCRIPTION:
% This function feeds one or more test signal(s) to the DUT(s) and records the response signal(s).
% 
% INPUT:
% X0: test signal with values ranging from -1...+1. For a single signal (same signal for all DAC output channels), X0 is a vector. For different signals, X0 is a matrix, with each column corresponding to one channel
% fs: the sampling rate to be used for the audio input / output (in Hz). Only sample rates supported by the hardware (or its driver software) are supported.
% latency: if the signal samples were specified rather than a file name/path, the signal is padded with zeros at its beginning and end to avoid cutting off the test signals early due to the latency of the sound input/output device(s). 'latency' is the length of the zero signals padded to the beginning and the end of the test signal (in seconds). If a file name is specified instead of the signal samples, the value of 'latency' is ignored.
% verbose (optional): If verbose=0, no information or feedback is displayed. Otherwise, mataa_measure_signal_response prints feedback on the progress of the sound in/out. If verbose is not specified, verbose ~= 0 is assumed.
% channels (optional): index to data channels obtained from the ADC that should be processed and returned. If not specified, all data channels are returned.
% cal (optional): calibration data for the full analysis chain DAC / SENSOR / ADC (see mataa_signal_calibrate_DUTin and mataa_signal_calibrate_DUTout for details). If different audio channels are used with different hardware (e.g., a microphone in the DUT channel and a loopback without microphone in the REF channel), separate structs describing the hardware of each channel can be provided in a cell array. If no cal is given or cal = [], the data will not be calibrated.
% 
% OUTPUT:
% dut_out: matrix containing the signal(s) at the DUT output(s) / SENSOR input(s) (all channels used for signal recording, each colum corresponds to one channel). If SENSOR and ADC cal data are available, these data are calibrated for the input sensitivity of the SENSOR and ADC.
% dut_in: matrix containing the signal(s) at the DAC(+BUFFER) output(s) / DUT input. If DAC cal data are available, these data are calibrated for the output sensitivity of the DAC(+BUFFER). This may also be handy if the original test-signal data are stored in a file, which would otherwise have to be loaded into into workspace to be used.
% t: vector containing the times corresponding the samples in dut_out and dut_in (in seconds)
% dut_out_unit: unit of data in dut_out. If the signal has more than one channel, signal_unit is a cell string with each cell reflecting the units of each signal channel.
% dut_in_unit: unit of data in dut_in (analogous to dut_out_unit)
% X0_RMS: RMS amplitude of signal at DUT input / DAC(+BUFFER) output (same unit as dut_in data). This may be different from the RMS amplitude of dut_in due to the zero-padding of dut_in in order to accomodate for the latency of the analysis system; the X0_RMS value is determined from the test signal before zero padding.
%
% FURTHER INFORMATION:
% The signal samples range from -1.0 to +1.0).
% The TestTone program feeds the X0 to both stereo channels of the output device, and records from both stereo channels of the input device (assuming we have a stereo device). Therefore, the response signal has two channels. As an example, channel 1 is used for for the DUT's response signal and channel 2 can be used to automatically calibrate for the frequency response / impulse response of the audio hardware (by directly connecting the audio output to the audio input). Channel allocation can be set using mataa_settings.
%
% EXAMPLE:
% (1) Feed a 1 kHz sine-wave signal to the DUT and plot the DUT output (no data calibration):
% > fs = 44100;
% > [s,t] = mataa_signal_generator ('sine',fs,0.2,1000);
% > [out,in,t,out_unit,in_unit] = mataa_measure_signal_response(s,fs,0.1,1,1);
% > plot (t,out);
% > xlabel ('Time (s)')
%
% (2) Feed a 1 kHz sine-wave signal to the DUT, use calibration as in GENERIC_CHAIN_DIRECT.txt file, and compare the input and response signals:
% > fs = 44100;
% > [s,t] = mataa_signal_generator ('sine',fs,0.2,1000);
% > [out,in,t,out_unit,in_unit] = mataa_measure_signal_response(s,fs,0.1,1,1,'GENERIC_CHAIN_DIRECT.txt');
% > subplot (2,1,1); plot (t,in); ylabel (sprintf('Signal at DUT input (%s)',in_unit));
% > subplot (2,1,2); plot (t,in); ylabel (sprintf('Signal at DUT output (%s)',out_unit));
% > xlabel ('Time (s)')
% 
% DISCLAIMER:
% This file is part of MATAA.
% 
% MATAA is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
% 
% MATAA is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with MATAA; if not, write to the Free Software
% Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
% 
% Copyright (C) 2006, 2007, 2008 Matthias S. Brennwald.
% Contact: info@audioroot.net
% Further information: http://www.audioroot.net/MATAA

if ~exist('verbose','var')
    verbose=1;
end

% check computer platform:
plat = mataa_computer;
if ( ~strcmp(plat,'MAC') && ~strcmp(plat,'PCWIN') && ~strcmp(plat,'LINUX_X86-32') && ~strcmp(plat,'LINUX_X86-64') && ~strcmp(plat,'LINUX_PPC')  && ~strcmp(plat,'LINUX_ARM_GNUEABIHF') )
	error('mataa_measure_signal_response: Sorry, this computer platform is not (yet) supported by the TestTone program.');
end

% check audio hardware:
audioInfo = mataa_audio_info;

switch plat
case 'MAC'
    desired_API = 'Core Audio';
case 'PCWIN'
    desired_API = 'ASIO';
case 'LINUX_X86-32'
    desired_API = 'ALSA';
case 'LINUX_X86-64'
    desired_API = 'ALSA';
case 'LINUX_PPC'
    desired_API = 'ALSA';
case 'LINUX_ARM_GNUEABIHF'
    desired_API = 'ALSA';
end
if ~strcmp (audioInfo.input.API,desired_API)
    warning (sprintf('mataa_measure_signal_response: The recommended sound API on your computer platform (%s) is %s, but your default input device uses another API (%s). Please see the MATAA manual.',plat,desired_API,audioInfo.input.API));
end
if ~strcmp (audioInfo.output.API,desired_API)
    warning (sprintf('mataa_measure_signal_response: The recommended sound API on your computer platform (%s) is %s, but you default output device uses another API (%s). Please see the MATAA manual.',plat,desired_API,audioInfo.output.API));
end

if strcmp(audioInfo.input.name,'(UNKNOWN)')
  error('mataa_measure_signal_response: No audio input device selected or no device available.');
end

if strcmp(audioInfo.output.name,'(UNKNOWN)')
   error('mataa_measure_signal_response: No audio output device selected or no device available.');
end

numInputChannels = audioInfo.input.channels;
if numInputChannels < 1
    error('mataa_measure_signal_response: The default audio input device has less than one input channel !?');
end

numOutputChannels = audioInfo.output.channels;

if ischar (X0)
	error ('mataa_measure_signal_response: use of this function with loading test signals from data files is not supported anymore. Pleas load the data first, then use this function with a vecor or matrix containing the test signal data.')
end

input_channels = size (X0,2);
if numOutputChannels < input_channels
	error(sprintf('mataa_measure_signal_response: input data has more channels (%i) than supported by the audio output device (%i).',input_channels,numOutputChannels));
end

if ~any(fs == audioInfo.input.sampleRates)
	warning(sprintf('The requested sample rate (%d Hz) is not listed for your audio input device. This is not always a problem, e.g. if the requested rate is available from sample-rate conversion by the operating system of if it is a non-standard rate that is not checked for by TestDevices but is supported by the audio hardware.',fs));
end

if ~any(fs == audioInfo.output.sampleRates)
	warning(sprintf('The requested sample rate (%d Hz) is not listed for your audio output device. This is not always a problem, e.g. if the requested rate is available from sample-rate conversion by the operating system of if it is a non-standard rate that is not checked for by TestDevices but is supported by the audio hardware.',fs));
end

% do the sound I/O:
deleteInputFileAfterIO = 0;

default_latency = 0.1 * max([1 fs/44100]); % just from experience with Behringer UMC202HD and M-AUDIO FW-410
if ~exist('latency','var')
	latency = [];
end
if isempty (latency)
	latency = default_latency;
	warning(sprintf('mataa_measure_signal_response: latency not specified. Assuming latency = %g seconds. Check for truncated data!',latency));
elseif latency < default_latency
	warning(sprintf('mataa_measure_signal_response: latency (%gs) is less than generic default (%gs). Make sure this is really what you want and check for truncated data!',latency,default_latency));
end
if verbose
	disp('Writing sound data to disk...');
end
in_path = mataa_signal_to_TestToneFile(X0,'',latency,fs);
if verbose
	disp('...done');
end
if ~exist(in_path,'file')
    error(sprintf('mataa_measure_signal_response: could not find input file (''%s'').',in_path));
end
deleteInputFileAfterIO = 1;
out_path = mataa_tempfile;

if exist('OCTAVE_VERSION','builtin')
	more('off'),
end
if verbose
    disp('Sound input / output started...');
    disp(sprintf('Sound output device: %s',audioInfo.output.name));
    disp(sprintf('Sound input device: %s',audioInfo.input.name));
    disp(sprintf('Sampling rate: %.3f samples per second',fs));
end

R = num2str(fs);

if strcmp(plat,'PCWIN')
    extension = '.exe';
else
    extension = '';
end    	

TestTone = sprintf('%s%s%s',mataa_path('TestTone'),'TestTonePA19',extension);

command = sprintf('"%s" %s %s > %s',TestTone,num2str(fs),in_path,out_path); % the ' are needed in case the paths contain spaces


status = -42; % in case the system command fails miserably, such that it does not even set the status flag
[output,status] = system(command);

if status ~= 0
    error('mataa_measure_signal_response: an error has occurred during sound I/O.')
end

if verbose
    disp('...sound I/O done.');
    disp('Reading sound data from disk...')
end


fid = fopen(out_path,'rt');
if fid == -1
	error('mataa_measure_signal_response: could not find input file.');
else
	frewind(fid);
	numChan = [];
	doRead = 1;
	while doRead % read the header
	    l = fgetl(fid);
	    % if findstr('Number of channels =',l) % for the old TestTone program
	    if findstr('Number of sound input channels =',l) % for the new TestTone program
	    	numChan = str2num(l(findstr('=',l)+1:end));
	    elseif findstr('time (s)',l) % this was the last line of the header
	    	doRead = 0;
	    elseif ~isempty(str2num(l));
	    	% if the 'time(s) ...' line is missing in the header for some reason...
	   		% this is the first line of the data
	   		doRead = 0;
	   		fseek(fid,ftell(fid)-length(l)-1); % go back to the end of the previous line so that we won't miss the first line of the data later on
	   	elseif l==-1
	   		warning('mataa_measure_signal_response:end of data file reached prematurely! Is the data file corrupted?');
	   		doRead = 0;
	    end 
	end
	if isempty(numChan)
		error('mataa_measure_signal_response: could not determine number of channels in recorded data.');
	end
	% read the data:
	out = fscanf(fid,'%f');
	l = length(out);
	if l < 1
		error('mataa_measure_signal_response: no data found in TestTone output file.');
	end
	out = reshape(out',numChan+1,l/(numChan+1))';
	fclose(fid);
end

if verbose
    disp('...data reading done.');
end

t=out(:,1);dut_out=out(:,2:end);

dut_in=load(in_path); % octave can easily read 1-row ASCII files

% clean up:
delete(out_path);
if deleteInputFileAfterIO
    delete(in_path);
end

% check if all channels of the ADC data are going to be used:
if ~exist ('channels','var')
	channels = [1:numChan];
end

% keep only ADC channels as given in channels, discard the rest:
dut_out = dut_out(:,channels);
numChan = length (channels);

if verbose
% check for clipping:
    for chan=1:numChan
    	m = max(abs(dut_out(:,chan)));
	m0 = 0.95;
    	if m >= m0
    		k = find(abs(dut_out(:,chan)) >= m0);
    		beep
    		disp(sprintf('Signal in channel %i may be clipped (%0.3g%% of all samples)!',channels(chan),length(k)/length(dut_out(:,1))*100));		
    		input('If you want to continue, press ENTER. To abort, press CTRL-C.');
    	else
    		u = '';
    		if channels(chan) == mataa_settings ('channel_DUT')
    			u = ' (DUT)';
    		elseif channels(chan) == mataa_settings ('channel_REF')
    			u = ' (REF)';
    		end
    		disp(sprintf('Max amplitude in channel %i%s: %0.3g%%',channels(chan),u,m*100));
    	end
    end
end

% calibrate data
X0_RMS = NA;
if ~exist ('cal','var')
	cal = [];
end
if isempty (cal)
	disp ('mataa_measure_signal_response: no calibration data available. Returning raw, uncalibrated data!')
	dut_out_unit = dut_in_unit = '???';
else
	if ischar(cal) % name of calibration file instead of cal struct
		cal = mataa_load_calibration (cal);
	end

	if isfield(cal,'DAC')
		% calibrate signal at DUT input for DAC(+BUFFER):
		RMS_raw = sqrt (sum(dut_in.^2 / length(dut_in)));
		[dut_in,t_in,dut_in_unit] = mataa_signal_calibrate_DUTin (dut_in,t,cal);
		RMS_cal = sqrt (sum(dut_in.^2 / length(dut_in)));

		% determine RMS amplitude of signal at DUT input (without zero padding):
		X0_RMS = RMS_cal/RMS_raw * sqrt (sum(X0.^2 / length(X0)));

	else
		warning ('mataa_measure_signal_response: cal data has no ADC data! Skipping calibration of signal at DUT input!')
	end


	if isfield(cal,'ADC')
		if isfield(cal,'SENSOR')
			[dut_out,t_out,dut_out_unit] = mataa_signal_calibrate_DUTout (dut_out,t,cal); % calibrate signal at DUT output for SENSOR and ADC
		else
			warning ('mataa_measure_signal_response: cal data has no SENSOR data! Skipping calibration of signal at DUT output!')
		end
	else
		warning ('mataa_measure_signal_response: cal data has no ADC data! Skipping calibration of signal at DUT input!')
	end

end

fflush (stdout);
