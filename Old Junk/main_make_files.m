clear;
clc;

%% GENERAL FLAGS
SAVE_FLAG = 1;

%% SPECIFY LOCATION TO SAVE INPUT FILES
%% Use if running on NERSC
%parentdir = uigetdir('$ME','Specify Save Directory'); %Use if running on NERSC cluster

%% Use if running on Windows
%parentdir = uigetdir('Z:','Specify Save Directory');
 
%% Use if running on Linux
addpath(genpath('/home/parkerwray/hypnos/Codes/MSTMwrapper'));  
addpath(genpath('/home/parkerwray/hypnos/Codes/Matlab Functions'));  
parentdir = uigetdir('/home/parkerwray/hypnos',' Specify Save Directory');

%% SPECIFY GENERAL PARAMETERS FOR MSTM RUN
%% Set flags for MSTM run
mstm_flags = struct('write_sphere_data', 1,...
    'store_translation_matrix', 0,...
    'normalize_scattering_matrix',0,...
    'fixed_or_random_orientation',0,...
    'calculate_scattering_coefficients',1,...
    'track_nearfield_iterations',1,...
    'calculate_near_field',0,...  
    'calculate_t_matrix', 0,...   
    'azimuth_average_scattering_matrix',0);

%% Define parameters for solution convergence
convergence = struct(...
    'mie_epsilon', 10^-9,...
    'translation_epsilon', 10^-9,...
    'solution_epsilon', 10^-9,...
    'max_number_iterations', 100000,...
    'plane_wave_epsilon',10^-9,...
    't_matrix_convergence_epsilon',10^-9,...    
    'sm_number_processors', 1000,...
    'iterations_per_correction', 30);

%% Define parameters for the input beam.
input_beam = struct(...
    'incident_or_target_frame', 0,... 
    'gaussian_beam_width', [],...
    'beam_type', 0,... % 0 = plane wave, 1 = Gaussian beam
    'incident_azimuth_angle_deg', 0,... % Alpha (Azimuth Direction)
    'incident_polar_angle_deg', 0,... % Beta (Zenith Direction)
    'polarization_angle_deg',0); % Gamma (Polarization Direction)

%% Define parameters for near field calculations
near_field = struct(...
    'plane_cord',2,...
    'plane_position',0,...
    'plane_vertices',[-3000,-3000,3000,6000],...
    'resolution',0.5,...
    'near_field_output_data',2);

%% Define parameters for particle distribution
mstm_input_params = struct(...
    'Nspheres', [],... 
    'k',[],...
    'real_ref_index_scale_factor', 1,...
    'imag_ref_index_scale_factor',1,...
    'real_chiral_factor', 0,...
    'imag_chiral_factor', 0,...
    'medium_real_ref_index',1,...
    'medium_imag_ref_index',0,...
    'medium_real_chiral_factor',0,...
    'medium_imag_chiral_factor',0);


%% SIMULATION MATERIAL AND CLUSTER PROPERTIES 
%% 
%{ 
Run files here that generate particle distributions that you want to
simulate. It is best that this code is determined by a secondary file that
can be called as a function. The output must have the standard format:
Input: 
    wavelengths
Output:
    spheres = [r, x, y, z, real RI, imag RI]
%}
wavelengths = 500;
spheres = Dual_Sphere_Anisotropic_Kerker_20_06_23(wavelengths);



mstm_input_params.Nspheres = size(spheres,1);
%% SIMULATION EXCITATION WAVE PARAMETERS

mstm_input_params.k = 2*pi./wavelengths;
if input_beam.beam_type == 1
    beam_waist = ceil(1./(0.19.*mstm_input_params.k)); % Spot RADIUS at focus
    Zr = (pi.*beam_waist.^2)./wavelengths; % Rayleigh range in [nm]
    disp(['The input beam diameter is ', num2str(2.*beam_waist), 'nm at focus'])
    disp(['The depth of field is ', num2str(2.*Zr), 'nm'])
    disp(['The unitless parameter is ', num2str(1./(k.*beam_waist)), ' (should be <= 0.2)'])
else
    beam_waist = 0;
end


%% GENERATE MSTM SIMULATION FILES TO RUN
%%

input_angle = 0:1:180;
% LOOP OVER PARAMETERS YOU WANT TO SWEEP
for idx = 1:length(input_angle)
    input_beam.incident_polar_angle_deg = input_angle(idx);
    
    fname{idx}= strcat('mstm_',... %GIVE A FILE NAME!
            sprintf( '%03d', idx ));

    % THIS FUNCTION GENERATES THE MSTM INPUTS
    make_mstm_job(parentdir,...
                        fname{idx},...
                        spheres,...
                        mstm_flags,...
                        convergence,...
                        input_beam,...
                        near_field,...
                        mstm_input_params) 
end
 
%% RUN SIMULATION FILES
%%
oldFolder = cd(parentdir);
if SAVE_FLAG == 1
    save('Simulation_Input_Workspace.mat');
    save('Simulation_Input_File.m');
end

%% Use if running on NERSC
% nodes = '2';
% time = '00:05:00';
% jobs = idx;
% make_mstm_SLURM_KNL_array_file(parentdir, nodes, time, jobs)

%% Use if running on Linux

% Copy mstm runfile to folder
mstm_location = '/home/parkerwray/hypnos/Codes/MSTMwrapper/mstm_parallel_ubuntu.out';
copyfile(mstm_location, parentdir);

% Run one parallelized simulation at a time
for idx = 1:length(fname)
    % Run MSTM code (Specify number of cores here)
    command{idx} = ['/usr/lib64/openmpi/bin/mpirun -n 6 ./mstm_parallel_ubuntu.out ',fname{idx},'.inp'];
    [status,cmdout] = system(command{idx},'-echo');
    %[status,cmdout] = system(command{idx});
end



%% EXTRACT MSTM DATA FOR POSTPROCESSING
%%


for idx = 1:length(fname)
    filename = strcat(parentdir,'/',fname{idx});
    [cluster_data{idx}, sphere_data{idx}, excitation_data{idx}] =...
        export_output_file_v2(strcat(filename,'_output.dat'));
    [sphere_coeff_data{idx}, alpha(idx), beta(idx), cbeam(idx),...
        m_med(idx), Nspheres(idx), Nequs(idx)] =...
        export_mstm_scattering_coeffs_v3(strcat(filename,'_scat_coeffs.dat'));
end

cluster = horzcat(cluster_data{:}).';
excitation = horzcat(excitation_data{:}).';
sphere_coeff = squeeze(cat(3, sphere_coeff_data{:}));


oldFolder = cd(parentdir);
if SAVE_FLAG == 1
    save('Simulation_Output_Workspace.mat');
end




% %[status,cmdout] = system(command,'-echo');
% [status,cmdout] = system(command{idx});
% 
% 
% 
% 
% 
% % Run multiple parallelized simulation at a time
% commands = [];
% for idx = 1:length(fname)
%     % Run MSTM code (Specify number of cores here)
%     command = ['/usr/lib64/openmpi/bin/mpirun -n 10 ./mstm_parallel_ubuntu.out ',fname{idx},'.inp'];
%     if idx > 1
%     dummy = [commands, ' && ',command];
%         if mod(idx,
%     %[status,cmdout] = system(command,'-echo');
%     [status,cmdout] = system(command);
% end
% 
% 
% 


