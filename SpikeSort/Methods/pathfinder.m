function path = pathfinder(targetNotebook, targetPage)

%% Make a dictionary from notebooks --> person
% Generates a path to the experiment folder so you can access data from other
% lab members without manually altering your functions. 

% Missing a notebook? just add it here under your name!
% Name not here? add it and then also add the path to your
% directory in the 2nd section

    notebooks = struct;
    notebooks.sonal = [927 945 970];
    notebooks.kathleen = [984 988 992 980 998];
    notebooks.ananya = [993];
    notebooks.yolanda = [995];
    notebooks.ani = [943];
    notebooks.james = [986];
    notebooks.dan = [901];
    notebooks.sara = [828 845 857];

    names = fieldnames(notebooks);
    
     % Make a dictionary for easy access on newer Matlab versions
     if ~verLessThan('matlab', '10')   
        
        d = dictionary;

        for i = 1:length(names)
    
            nbs = notebooks.(names{i});
    
            for j = 1:length(nbs)
                d = insert(d, nbs(j), names{i});
            end

        end
        person = d(targetNotebook);

    % Just use structures for older versions
    else

        nums = struct;
        for i = 1:length(names)
            nbs = notebooks.(names{i});

            for j = 1:length(nbs)
                nums.("NB_" + string(nbs(j))) = names{i};
            end

        end
        try
        person = nums.("NB_" + string(targetNotebook));
        catch
            ME = MException('MyComponent:noSuchVariable', "Add notebook " + targetNotebook + " to pathfinder.");
            throw(ME);
        end
        
            
    end

    
    %% Paths for different platforms (only mac implemented so far)
    paths = struct;
    if ismac
        paths.sonal = "/Volumes/marder-lab/skedia/Sonal_data/";
        paths.kathleen = "/Volumes/marder-lab/kjacquerie/_raw data/";
        paths.ananya = "/Volumes/marder-lab/adalal/Data/";
        paths.yolanda = "/Volumes/marder-lab/ylli/";
        paths.ani = "/Volumes/marder-lab/apoghosyan/raw data/";
        paths.james = "/Volumes/marder-lab/jdimartino/";
        paths.dan = "/Volumes/marder-lab/Move_To_Archive/daniel_powell/GMR/";
        paths.sara = "/Volumes/marder-lab/Move_To_Archive/sara_haddad/828/";
        

    else
        disp("not implemented for windows yet sorry mb")
    end


    try
    
    path = paths.(person) + targetNotebook + "_" + sprintf('%03d',targetPage) + "/";
    catch
        disp("target notebook not found, update this script.")
    end
    

    

