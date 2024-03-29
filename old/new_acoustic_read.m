%% cleanup first, set global parameters
close all
clearvars
home

% data storage location
datastor = 'local'; % 'local' if dataset copied to local drive, 'gel-nas1', or 'enacdrives'

%% choose dataset and load acquisition times
switch datastor
    case 'gel-nas1'
        % data path on gel-nas1
        datapath = pathbyarchitecture('gel-nas1');
    case 'enacdrives'
        datapath = pathbyarchitecture('enac1files');
    case 'local'
        [~, username] = system('whoami');
        datapath = ['/home/' username(1:end-1) '/data/'];
end
% 2018 acquisitions
datayear = 18;
% injection on slate
datamonth = 11;
dataday = 27;
starttime = '142253';

% data folder name from experiment date
datafold = [num2str(datayear,'%02d') '-' num2str(datamonth,'%02d') '-' ...
    num2str(dataday,'%02d') '/'];
% extract timestamp list and other "low frequency" measurement data
fid = fopen([datapath datafold num2str(starttime) '.txt'],'r');
hdrcol = 15;
hdrData = textscan(fid,'%s',hdrcol);
CellData = textscan(fid,'%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f');
fclose(fid);
HH = floor(CellData{1}./1E4);
mm = floor((CellData{1}-1E4*HH)./1E2);
ss = floor(CellData{1}-1E4*HH-1E2*mm);
colons = repmat(':',size(HH));
CellTimes = [num2str(HH) colons num2str(mm) colons num2str(ss)];
AcqTime = timestamps(CellTimes,datayear,datamonth,dataday);

% extract header info from JSON file
fjson = [datapath datafold num2str(starttime) '.json'];
jsonhdr = jsondecode(fileread(fjson));

%% pressure/volume profile and other LF measurements
% plot pressure gauge data
PressureGauge = [CellData{2} CellData{3}]; % pressure in MPa
figure
plot(AcqTime,PressureGauge)
xlim([AcqTime(1) AcqTime(end)])
ylim([0 40])
xlabel('Time')
ylabel('Pressure (MPa)')
% show only time on x-axis
datetick('x',15)

hold on
plot(AcqTime,CellData{10}/1E3)

%% load data from bin file
% read active acoustic parameters from JSON header
ActiveAcoustic = jsonhdr.ActiveAcousticInfos;
% extract relevant parameters
ns = ActiveAcoustic.NumberOfPoints;
nt = ActiveAcoustic.NumberOfSources;
nr = ActiveAcoustic.NumberOfReceivers;
Fs = ActiveAcoustic.SamplingFrequency_MHz_*1E6;
dt = 1/Fs;  % time step
t0 = 0;     % initial time
T = t0+dt*linspace(0,ns-1,ns)'; % time vector
Fn = 0.5*Fs;    % Nyquist frequency (Hz)
seqsize = ns*nt*nr*8;   % size in bytes of one single acquisition sequence

% open bin data file and read header size (recorded in first double in bin)
fid = fopen([datapath datafold num2str(starttime) '.bin'],'r');
hdrsize = (fread(fid,1,'double')+1)*8;
% check bin file size and get number of acquisition sequences
binstats = dir([datapath datafold num2str(starttime) '.bin']);
if ~isequal(mod(binstats.bytes,seqsize),hdrsize)
    disp('incomplete acquisition sequence')
end
nq = floor(binstats.bytes/seqsize); % number of acquisition sequences

% read data file
q0 = 1; % initial sequence to read (first one is 1)
qq = 5; % number of sequences to read
if q0+qq-1>nq
    disp('trying to read non-existant sequences')
end

% set pointer to beginning of binary data for q0 sequence
fseek(fid,hdrsize+(q0-1)*seqsize,'bof');

% create empty arrays
datatmp = zeros(qq,ns,nr*nt);
datafilt = zeros(size(datatmp));
% DC filter definition for signal cleanup
a = [1,-0.99];
b = [1,-1];
for ii = q0:q0+qq-1
    datatmp(ii-q0+1,:,:) = fread(fid,[ns,nt*nr],'double');
    % DC filter with a and b coefficients
    datafilt(ii-q0+1,:,:) = filtfilt(b,a,squeeze(datatmp(ii-q0+1,:,:)));
end
fclose(fid);
% reshape data arrays to 4D
dataInit2 = reshape(datatmp,qq,ns,nr,nt);
dataInit3 = reshape(datafilt,qq,ns,nr,nt);

%% plot them
% time plot
jj = 7; % source-receiver pair
figure
disp(['plotting source-receiver #' num2str(jj) ' amplitude over time'])
plot(T*1E6,dataInit2(:,:,jj,jj),T*1E6,dataInit3(:,:,jj,jj))
xlabel('Time (\mus)')
ylabel('Amplitude (a.u.)')
title(['source-receiver #' num2str(jj)])

% image plot
kk = 7; % source number
figure, imagesc(0:nr-1,T*1E6,squeeze(dataInit3(1,:,:,kk)))
disp(['plotting receivers for source #' num2str(kk) 'over time'])
caxis([-1 1]*0.002)
colormap('jet')
colorbar
axis([0 nr-1 0 150])
xlabel('Receiver number')
ylabel('Time (\mus)')
title(['Source number ' num2str(kk)])

%% look for good source-receiver pairs
D = reshape(squeeze(dataInit2(1,:,:,:)),[],nr*nt); % flatten 3D array
Dd = squeeze(D(:,1:nr+1:end)); % extract 'diagonal'
clearvars D

% check all on-axis pairs
figure
disp('plotting all on-axis pairs')
plot(T*1E6,Dd)

% remove excitation noise
endnoise = 100;
% L2 norm 
N = sqrt(sum(Dd(endnoise:end,:).^2,1));
% plot L2 norm strength
figure
disp('plotting plot L2 norm strength')
bar(1:nr,N)
axis([0.5 nr+0.5 0 max(N)])
xlabel('Source-receiver pair')
ylabel('Signal strength')

