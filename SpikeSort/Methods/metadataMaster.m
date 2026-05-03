% Load an experiment more easily using existing saved metadata
% Make sure notebook path is saved in pathfinder.m

function[metadata] = metadataMaster()

% You can call another metadata file to add to a structure metadata
%sonalMetadata
%kathleenMetadata

%% Use this template

NB = 901;
page = 80;

metadata(NB, page).acclimation = 11;
metadata(NB, page).channels.temp = 'Temp';
metadata(NB, page).channels.lgn = 'IN 5';
metadata(NB, page).tempValues = [7 11 15 19 21];
metadata(NB, page).files = [15 24 34 42 48];
%%
NB = 901;
page = 95;

metadata(NB, page).acclimation = 4;
metadata(NB, page).channels.temp = 'Temp';
metadata(NB, page).channels.lgn = 'IN 9';
metadata(NB, page).tempValues = [7 11 15 19 21];
metadata(NB, page).files = [17 22 32 60 65];

%%