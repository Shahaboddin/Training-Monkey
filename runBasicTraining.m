function runBasicTraining(ana)

global lM
switch ana.lJType
	case 'T4'
		if ~isa(lM,'labJackT');lM = labJackT('openNow',false);end
		lM.strobeTime = 10; %make strobe time a bit longer for EEG 
	otherwise
		if ~isa(lM,'labJack');lM = labJack('openNow',false,'readResponse',false);end
		lM.strobeTime = 64;
end
if ~ana.sendTrigger; lM.silentMode = true; end
if ~lM.isOpen; open(lM); end %open our strobed word manager

global rM
if ~exist('rM','var') || isempty(rM)
	rM = arduinoManager();
end
if ~ana.useArduino
	rM.silentMode = true; 
	ana.rewardDuring=false;
	ana.rewardEnd=false;
	ana.rewardStart=false;
end
if ~rM.isOpen; open(rM); end %open our reward manager

fprintf('\n--->>> runBasicTraining Started: ana UUID = %s!\n',ana.uuid);

%===================Initiate our metadata===================
ana.date		= datestr(datetime);
ana.version		= Screen('Version');
ana.computer	= Screen('Computer');
ana.gpu			= opengl('data');
thisVerbose		= false;

%===================experiment parameters===================
ana.screenID	= max(Screen('Screens'));%-1;

%===================Make a name for this run===================
ana.timeExp		= fix(clock());
if ~isempty(ana.subject)
	nameExp		= [ana.subject];
	c			= sprintf(' %i',ana.timeExp);
	nameExp		= [nameExp c '_' ana.stimulus];
	ana.nameExp = regexprep(nameExp,' ','_');
else
	ana.nameExp = 'debug';
end

cla(ana.plotAxis1);
cla(ana.plotAxis2);
rewardtime = 250; % in ms, pump normally needs a minimum of 250ms to trigger

%==========================TRY==========================
try
	PsychDefaultSetup(2);Screen('Preference', 'SkipSyncTests', 0)
	%===================open our screen====================
	sM						= screenManager();
	sM.screen				= ana.screenID;
	sM.verbose				= thisVerbose;
	sM.bitDepth				= 'FloatingPoint32BitIfPossible';
	if ana.debug || ismac || ispc || ~isempty(regexpi(ana.gpu.Vendor,'NVIDIA','ONCE'))
		sM.disableSyncTests = true; 
	end
	if ana.debug
		%sM.windowed			= [0 0 1400 1000]; 
		sM.visualDebug		= true;
		sM.debug			= true;
		sM.verbosityLevel	= 5;
	else
		sM.debug			= false;
		sM.verbosityLevel	= 3;
	end
	sM.backgroundColour		= ana.backgroundColour;
	sM.pixelsPerCm			= ana.pixelsPerCm;
	sM.distance				= ana.distance;
	sM.blend				= true;
	if isfield(ana,'screenCal') && exist(ana.screenCal, 'file')
		load(ana.screenCal);
		if exist('c','var') && isa(c,'calibrateLuminance')
			sM.gammaTable	= c;
		end
		clear c;
	end
	sM.open;
	ana.gpuInfo				= Screen('GetWindowInfo',sM.win);
	fprintf('\n--->>> BasicTraining Opened Screen %i : %s\n', sM.win, sM.fullName);
	
	PsychPortAudio('Close');
	sM.audio = audioManager(); sM.audio.close();
	if IsLinux
		sM.audio.device		= [];
	elseif IsWin
		sM.audio.device		= [];
	end
	sM.audio.setup();
	
	%===========================tobii manager=====================
	eT						= tobiiManager();
	eT.name					= ana.nameExp;
	eT.model				= ana.tracker;
	eT.trackingMode			= ana.trackingMode;
	eT.eyeUsed				= ana.eyeUsed;
	eT.sampleRate			= ana.sampleRate;
	eT.calibrationStimulus	= ana.calStim;
	eT.manualCalibration	= ana.calManual;
	eT.calPositions			= ana.calPos;
	eT.valPositions			= ana.valPos;
	eT.autoPace				= ana.autoPace;
	eT.paceDuration			= ana.paceDuration;
	eT.smoothing.nSamples	= ana.nSamples;
	eT.smoothing.method		= ana.smoothMethod;
	eT.smoothing.window		= ana.w;
	eT.smoothing.eyes		= ana.smoothEye;
	if ~ana.isDummy; eT.verbose	= true; end
	if ~ana.useTracker || ana.isDummy
		eT.isDummy			= true;
	end
	if length(Screen('Screens')) > 1 && sM.screen - 1 >= 0 && ana.useTracker% ---- second screen for calibration
		s					= screenManager;
		s.verbose			= thisVerbose;
		s.screen			= sM.screen - 1;
		s.backgroundColour	= sM.backgroundColour;
		s.distance			= sM.distance;
		[w,h]				= Screen('WindowSize',s.screen);
		s.windowed			= [0 0 round(w/2) round(h/2)];
		s.blend				= sM.blend;
		s.bitDepth			= '8bit';
		s.blend				= true;
		s.pixelsPerCm		= 30;
	end
	if exist('s','var')
		initialise(eT,sM,s);
	else
		initialise(eT,sM);
	end
	
	eT.settings.cal.doRandomPointOrder  = false;
	ana.cal=[];
	if isempty(ana.calFile) || ~exist(ana.calFile,'file')
		name = regexprep(ana.subject,' ','_');
		ana.calFile = [eT.paths.savedData filesep 'TobiiCal-' name '.mat'];
	end
	if ana.reloadPreviousCal && exist(ana.calFile,'file')
		load(ana.calFile);
		if isfield(cal,'attempt') && ~isempty(cal.attempt); ana.cal = cal; end
	end
	cal = trackerSetup(eT, ana.cal); ShowCursor();
	if ~isempty(cal) && isfield(cal,'attempt')
		cal.comment=sprintf('Subject:%s | Comments: %s | tobii calibration',ana.subject,ana.comments);
		cal.computer = ana.computer;
		cal.date = ana.date;
		assignin('base','cal',cal); %put our calibration ready to save manually
		save(ana.calFile,'cal');
		ana.outcal = cal;
	end
	
	% ---- initial fixation values.
	eT.resetFixation();
	eT.fixation.X			= ana.XFix;
	eT.fixation.Y			= ana.YFix;
	eT.fixation.initTime	= ana.initTime;
	eT.fixation.fixTime		= ana.fixTime;
	eT.fixation.radius		= ana.radius;
	eT.fixation.strict		= ana.strict;
	
	%===========================set up stimuli====================
	
	ana.fixOnly			= false;
	ana.moveStim		= false;
	ana.isVEP			= false;
	ana.isGaze			= false;
	seq.taskFinished	= false;
	
	if strcmpi(ana.stimulus,'Dancing Monkey')
		stim				= movieStimulus();
		stim.size			= ana.size;
		stim.setup(sM);
		ana.moveStim		= true;
	elseif strcmpi(ana.stimulus,'Pictures')
		stim				= imageStimulus();
		stim.size			= ana.size;
		stim.fileName		= ana.imageDir;
		stim.setup(sM);
		ana.moveStim		= true;
		eT.secondScreen = false; %fix opengl window bug
	elseif strcmpi(ana.stimulus,'Gaze Training')
		stim				= imageStimulus();
		stim.size			= 30;
		stim.fileName		= ana.imageDir;
		stim.setup(sM);
		ana.isGaze			= true;
		picSize.X = 28; % in degree gazepic=1200*900,around 28degree
		if  stim.size >0
			picSize.X = stim.size;
		end
		picSize.Y = picSize.X*3/4;
		eT.secondScreen = false; %fix opengl window bug
		
	elseif strcmpi(ana.stimulus,'VEP')
		stim									= metaStimulus();
		switch ana.VEP.Type
			case 'Checkerboard'
				stim.stimuli{1}					= barStimulus();
				if ana.size == 0 || ana.size == inf
					stim.stimuli{1}.barWidth	= ceil(sM.screenVals.width / sM.ppd);
					stim.stimuli{1}.barHeight	= ceil(sM.screenVals.height / sM.ppd);
				else
					stim.stimuli{1}.size		= ana.size;
				end
				stim.stimuli{1}.type			= 'checkerboard';
				eT.secondScreen = false; %fix opengl window bug
				eT.manualCalibration = false;
			case {'Square','Sin'}
				stim.stimuli{1}					= gratingStimulus();
				if ana.size == 0 || ana.size == inf
					stim.stimuli{1}.size		= ceil(sM.screenVals.width / sM.ppd);
				else
					stim.stimuli{1}.size		= ana.size;
				end
				if strcmpi(ana.VEP.Type,'Square')
					sM.srcMode					= 'GL_ONE';
					sM.dstMode					= 'GL_ZERO';
					stim.stimuli{1}.type		= 'square';
				end
				stim.stimuli{1}.tf				= 0;
				stim.stimuli{1}.mask			= ana.VEP.mask;
			case 'LogGabor'
				stim.stimuli{1}					= logGaborStimulus();
				if ana.size == 0 || ana.size == inf
					stim.stimuli{1}.size	= ceil(sM.screenVals.width / sM.ppd);
				else
					stim.stimuli{1}.size		= ana.size;
				end
				stim.stimuli{1}.sf				= ana.VEP.sfPeak;
				stim.stimuli{1}.sfSigma			= ana.VEP.sfSigma;
				stim.stimuli{1}.angle			= ana.VEP.anglePeak;
				stim.stimuli{1}.angleSigma		= ana.VEP.angleSigma;
				stim.stimuli{1}.mask			= ana.VEP.mask;
				eT.secondScreen = false; %fix opengl window bug
				eT.manualCalibration = false;
		end
		stim.stimuli{1}.speed					= 0;
		stim.stimuli{1}.phaseReverseTime		= ana.VEP.Flicker;
		stim.stimuli{1}.verbose					= thisVerbose;
		
		stim.stimuli{2}							= discStimulus();
		stim.stimuli{2}.size					= ana.spotSize+0.1;
		stim.stimuli{2}.alpha					= 0.1;
		stim.stimuli{2}.colour					= ana.backgroundColour;
		stim.setup(sM);
		if ana.spotSize < 1; stim.stimuli{2}.hide(); end
		ana.isVEP			= true;
		
		%=====================Stimulus Sequence=========================
		seq					= stimulusSequence();
		seq.nBlocks			= ana.nBlocks;
		seq.addBlank		= ana.addBlank;
		seq.nVar(1).name	= 'sf';
		if size(ana.VEP.SF,1) > size(ana.VEP.SF,2)
			if ana.VEP.LogSF
				seq.nVar(1).values	= logspace(log10(ana.VEP.SF(1)),log10(ana.VEP.SF(2)),ana.VEP.SF(3));
			else
				seq.nVar(1).values	= linspace(ana.VEP.SF(1),ana.VEP.SF(2),ana.VEP.SF(3));
			end
		else
			seq.nVar(1).values = ana.VEP.SF;
		end
		seq.nVar(1).values = unique(seq.nVar(1).values);
		seq.nVar(1).stimulus = 1;
		
		seq.nVar(2).name	= 'contrast';
		if size(ana.VEP.Contrast,1) > size(ana.VEP.Contrast,2)
			if ana.VEP.LogContrast
				seq.nVar(2).values	= logspace(log10(ana.VEP.Contrast(1)),log10(ana.VEP.Contrast(2)),ana.VEP.Contrast(3));
			else
				seq.nVar(2).values	= linspace(ana.VEP.Contrast(1),ana.VEP.Contrast(2),ana.VEP.Contrast(3));
			end
		else
			seq.nVar(2).values = ana.VEP.Contrast;
		end
		seq.nVar(2).values = unique(seq.nVar(2).values);
		seq.nVar(2).stimulus = 1;
		
		initialise(seq);
		ana.nTrials = seq.nRuns;
	else
		%===============================FIXATION ONLY
		ana.fixOnly			= true;
		ana.moveStim		= true;
		if ana.size == 0; ana.size = 0.6; end
	end
	
	pos = ana.positions;
	posLoop = 1;
	
	%=================set up eye position drawing================
	switch lower(ana.drawEye)
		case 'same screen'
			drawEye = 1;
		case 'new screen'
			if exist('s','var') && isa(s,'screenManager')
				if isempty(eT.operatorScreen); eT.operatorScreen = s; eT.secondScreen=true; end
				if ~s.isOpen; s.open; end
				drawEye = 2;
				refRate = 3; %refresh window every N frames
			else
				drawEye = 1;
			end
		otherwise
			drawEye = 0;
	end
	
	
	%===========================prepare===========================
	Priority(MaxPriority(sM.win)); %bump our priority to maximum allowed
	if ana.sendTrigger
		sd = ana.timeExp;
		sd(1)=20;
		for i = 1:3;lM.strobeServer(255);WaitSecs(0.02); end
		for i = 1:length(sd);lM.strobeServer(sd(i));WaitSecs(0.02);end
	end
	startRecording(eT, true); WaitSecs('YieldSecs',1);
	trackerMessage(eT,'!!! Starting Session...');
	breakLoop		= false;
	ana.trial		= struct();
	thisRun			= 0;
	rewards			= 0;
	pfeedback		= 0;
	nfeedback		= 0;
	
	while ~breakLoop
		%=================================TRIAL SETUP================================
		thisRun = thisRun + 1;
		tit = sprintf('\n===>>> BasicTraining START Run = %i | %s',...
				thisRun, sM.fullName);
		if ana.moveStim && ~ana.isVEP
			if ana.randomPosition
				thisPos = pos(randi(length(pos)),:);
			else
				thisPos = pos(posLoop,:);
				posLoop = posLoop + 1;
				if posLoop > size(pos,1); posLoop = 1; end
			end
			eT.fixation.X = thisPos(1);
			eT.fixation.Y = thisPos(2);
			if ~ana.fixOnly
				stim.xPositionOut = thisPos(1);
				stim.yPositionOut = thisPos(2);
			end
			tit = sprintf('%s pos = %i %i',...
				tit,thisPos(1),thisPos(2));
		else
			thisPos = [ana.XFix, ana.YFix];
			eT.fixation.X = thisPos(1);
			eT.fixation.Y = thisPos(2);
		end
		if ana.isVEP
			thisRun = seq.outIndex(seq.totalRuns);
			if isnan(seq.outValues{seq.totalRuns,1})
				hide(stim);
				fprintf('BLANK STIMULUS CONDITION\n');
			else
				show(stim);
				if ana.spotSize == 0; stim.stimuli{2}.hide(); end
				stim.stimuli{1}.sfOut = seq.outValues{seq.totalRuns,1};
				stim.stimuli{1}.contrastOut = seq.outValues{seq.totalRuns,2};
			end
			tit = sprintf('\n===>>> BasicTraining START Run = %i (%i:%i) | %s | SF = %.2f | Contrast = %.2f\n', ...
			  thisRun, seq.totalRuns, seq.nRuns, sM.fullName,seq.outValues{seq.totalRuns,1},seq.outValues{seq.totalRuns,2});
		end
		
		if ~ana.fixOnly
			update(stim); 
		end
		
		fprintf('%s\n',tit);
		
		trackerMessage(eT,['TRIALID ' num2str(thisRun)]);
		trackerMessage(eT,['MSG:Position=' num2str(thisPos)]);
		
		%========================================================INITIATE FIXATION
		tick = 0;
		eT.resetFixation();
		fixated = ''; doBreak = false;
		if ana.initFix
			if ana.useTracker
				if ~ana.debug;ListenChar(-1); end
				while ~strcmpi(fixated,'fix') && ~strcmpi(fixated,'breakfix')
					if ana.spotSize > 0;sM.drawCross(ana.spotSize,[],thisPos(1),thisPos(2),ana.spotLine,true,ana.spotAlpha);end
					if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
					if drawEye==1 
						drawEyePosition(eT,true);
					elseif drawEye==2 && mod(tick,refRate)==0
						drawText(s,tit);drawGrid(s);trackerDrawFixation(eT);
					end
					finishDrawing(sM);
					if tick == 1; trackerMessage(eT,'INITIATE_FIX',vbl); end
					getSample(eT);
					fixated=testSearchHoldFixation(eT,'fix','breakfix');
					doBreak = checkKeys();
					if doBreak; break; end
					vbl = flip(sM); tick = tick + 1;
					if drawEye==2 && mod(tick,refRate)==0; flip(s,[],[],2);end
				end
				ListenChar(0);
				trackerMessage(eT,'END_FIX',vbl)
				if strcmpi(fixated,'breakfix')
					fprintf('===>>> BROKE INITIATE FIXATION Trial = %i\n', thisRun);
					trackerMessage(eT,'TRIAL_RESULT -100');
					trackerMessage(eT,'MSG:BreakInitialFix');
					if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
					Screen('Flip',sM.win); %flip the buffer
					WaitSecs('YieldSecs',0.5);
					continue
				end
			else
				if ana.spotSize > 0;sM.drawCross(ana.spotSize,[],thisPos(1),thisPos(2),ana.spotLine,true,ana.spotAlpha);end
				if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
				finishDrawing(sM);
				flip(sM);
				WaitSecs(0.5);
			end
		else
			fixated = 'fix';
		end
		
		%===========================================================SHOW STIMULUS
		tick = 0;
		gracePeriod = round( ana.graceTime / sM.screenVals.ifi);
		kTimer = 0; % this is the timer to stop too many key events
		thisResponse = -1; doBreak = false;
		if ana.spotSize > 0;sM.drawCross(ana.spotSize,[],thisPos(1),thisPos(2),ana.spotLine,true,ana.spotAlpha);end
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		if ana.isGaze; eT.fixation.X = 0; eT.fixation.Y = 0; eT.fixation.Xradius = picSize.X/2;eT.fixation.Yradius=picSize.Y/2; end 
		if ana.rewardStart; rM.timedTTL(2,rewardtime); rewards=rewards+1; end
% 		if ~ana.isVEP; play(sM.audio); end
		tStart = flip(sM); vbl = tStart;
		while vbl < tStart + ana.playTimes
			if ana.fixOnly
				drawCross(sM,ana.size,[],thisPos(1),thisPos(2));
			else
				draw(stim);
				if ana.isVEP
					if ana.spotSize > 0
						if ana.spotAlpha == 1
							sM.drawCross(ana.spotSize,[],thisPos(1),thisPos(2),...
							ana.spotLine,true,ana.spotAlpha)
						else
							sM.drawCross(ana.spotSize,[],thisPos(1),thisPos(2),...
							ana.spotLine,true,ana.spotAlpha/2)
						end
					end
				else
% 					sM.drawCross(0.5,[],thisPos(1),thisPos(2),0.05,true,0.2);
				end
			end
			if ana.photoDiode; drawPhotoDiodeSquare(sM,[1 1 1]); end
			if drawEye==1 
				drawEyePosition(eT,true);
			elseif drawEye==2 && mod(tick,refRate)==0
				drawGrid(s);trackerDrawFixation(eT);
			end
			if sM.visualDebug; sM.drawGrid(); end
			finishDrawing(sM);
			
			if ~ana.fixOnly; animate(stim); end
			getSample(eT);
			if tick <= gracePeriod
				fixated = 'fix';
			else
				if ana.useTracker && ~isFixated(eT);fixated = 'breakfix'; break; end
			end
			doBreak = checkKeys(); if doBreak; break; end
			
			vbl = flip(sM,vbl); tick = tick + 1;
			if tick==1 
				if ana.sendTrigger; lM.strobeServer(thisRun); end
				trackerMessage(eT,'SHOW_STIMULUS',vbl);
			end
			if drawEye==2 && mod(tick,refRate)==0; flip(s,[],[],2);end

			if ana.rewardDuring && tick == 60;rM.timedTTL(2,rewardtime);rewards=rewards+1;end
		end
		
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		vbl						= flip(sM);
		if ana.sendTrigger;lM.strobeServer(255); end
		tEnd					= vbl;
		eT.fixation.radius		= ana.radius;
		if drawEye==2;flip(s,[],[],2);end
		
		%=============================================================CHECK RESPONSE
		if strcmpi(fixated,'breakfix') || thisResponse == 0
			trackerMessage(eT,'END_VBL',tEnd);
			trackerMessage(eT,'TRIAL_RESULT -1');
			trackerMessage(eT,'MSG:BreakFix');
			fprintf('===>>> Fixation broken in %.2f secs\n',tEnd-tStart)
			if ~doBreak; incorrect(); end
		elseif strcmpi(fixated,'fix') || thisResponse == 1
			trackerMessage(eT,'END_VBL',tEnd);
			trackerMessage(eT,'TRIAL_RESULT 1');
			if ~doBreak; correct(); end
		elseif ~doBreak
			if ana.rewardEnd; rM.timedTTL(2,rewardtime); rewards=rewards+1;beep(sM.audio,'high'); end
			if ana.isVEP
				updateTask(seq,true,tEnd-tStart); %updates our current run number
				if seq.taskFinished;breakLoop = true;end
			end
			if ana.sendTrigger;WaitSecs(0.02);lM.strobeServer(250); end
			if drawEye==2
				drawEyePositions();
			end
			WaitSecs('UntilTime',tEnd+ana.ITI);
			if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
			flip(sM);
		end
		
		sM.audio.loadSamples();
		updatePlots();
		
		%========================================================SAVE THIS RUN INFO
		if ana.isVEP
			ana.trial(seq.totalRuns).n = seq.totalRuns;
			ana.trial(seq.totalRuns).variable = seq.outIndex(seq.totalRuns);
			ana.trial(seq.totalRuns).result = thisResponse;
			ana.trial(seq.totalRuns).rewards = rewards;
			ana.trial(seq.totalRuns).positive = pfeedback;
			ana.trial(seq.totalRuns).negative = nfeedback;
			ana.trial(seq.totalRuns).tStart = tStart;
			ana.trial(seq.totalRuns).tEnd = tEnd;
			ana.trial(seq.totalRuns).tick = tick;
		else
			ana.trial(thisRun).result = thisResponse;
			ana.trial(thisRun).position = thisPos;
			ana.trial(thisRun).rewards = rewards;
			ana.trial(thisRun).positive = pfeedback;
			ana.trial(thisRun).negative = nfeedback;
			ana.trial(thisRun).tStart = tStart;
			ana.trial(thisRun).tEnd = tEnd;
			ana.trial(thisRun).tick = tick;
		end
	end %=====================================while ~breakLoop
	
	%===============================Clean up============================
	fprintf('\n===>>> basicTraining Finished Trials: %i\n',thisRun);
	drawTextNow(sM, '===>>> FINISHED!!!');
	if drawEye==2; drawTextNow(sM, '===>>> FINISHED!!!'); end
	if ana.sendTrigger
		sd = ana.timeExp;
		sd(1)=20;
		for i = 1:3;lM.strobeServer(255);WaitSecs(0.02); end
		for i = 1:length(sd);lM.strobeServer(sd(i));WaitSecs(0.02);end
	end
	WaitSecs('YieldSecs', 0.25);
	stopRecording(eT);
	saveData(eT,false);
	if exist('s','var') && isa(s,'screenManager'); s.close; end
	close(sM);
	if drawEye==2;close(s);end
	
	if exist(ana.ResultDir,'dir') > 0
		cd(ana.ResultDir);
	end
	
	if ~isempty(ana.nameExp) || ~strcmpi(ana.nameExp,'debug')
		ana.plotAxis1 = [];
		ana.plotAxis2 = [];
		fprintf('==>> SAVE %s, to: %s\n', ana.nameExp, pwd);
		save([ana.nameExp '.mat'],'ana','eT','sM','seq');
		assignin('base','ana',ana)
		assignin('base','seq',seq)
	end
	
	ListenChar(0);ShowCursor;Priority(0);
	clear ana seq eT sM tL cM
	
catch ME
	getReport(ME)
	assignin('base','ana',ana)
	if exist('sM','var') && isa(sM,'screenManager'); close(sM); end
	if exist('s','var') && isa(s,'screenManager'); close(s); end
	ListenChar(0);ShowCursor;Priority(0);Screen('CloseAll');
end

	function doBreak = checkKeys()
		doBreak = false;
		[keyIsDown, ~, keyCode] = KbCheck(-1);
		if keyIsDown == 1
			rchar = KbName(keyCode);if iscell(rchar); rchar=rchar{1}; end
			switch lower(rchar)
				case {'q','0','escape'}
					Screen('DrawText', sM.win, '===>>> EXIT!!!',10,10);
					flip(sM);
					fprintf('===>>> EXIT!\n');
					fixated = 'breakfix';
					breakLoop = true;
					doBreak = true;
				case {'p'}
					fprintf('===>>> PAUSED!\n');
					Screen('DrawText', sM.win, '===>>> PAUSED, press key to resume!!!',10,10);
					flip(sM);
					WaitSecs('Yieldsecs',0.1);
					KbWait(-1);
					fixated = 'breakfix';
					doBreak = true;
				case {'c'}
					WaitSecs('YieldSecs',0.1);
					fprintf('\n\n--->>> Entering calibration mode...\n');
					if isempty(regexpi(ana.VEP.Type,'Sin|Square'))
						trackerSetup(eT);
					else
						trackerSetup(eT,eT.calibration);
					end
					fixated = 'breakfix';
					doBreak = true;
				case {'1','1!','kp_end'}
					if kTimer < vbl
						kTimer = vbl + 0.2;
						rM.timedTTL(2,rewardtime);
						rewards = rewards + 1;
					end
				case {'2','2@','kp_down'}
					correct();
					doBreak = true;
				case {'3','3#','kp_next'}
					incorrect();
					doBreak = true;
			end
		end
	end

	function updatePlots()
		b = bar(ana.plotAxis1, rewards);
		b.Parent.XTickLabel = {''};
		b = bar(ana.plotAxis2, [1 2], [pfeedback nfeedback]);
		title(ana.plotAxis2,sprintf('Responses [correct rate = %.2f]',...
			(1/((pfeedback+nfeedback)/pfeedback))*100));
		b.Parent.XTickLabel = {'positive','negative'};
		drawnow;
	end

	function correct()
		if ana.rewardEnd; rM.timedTTL(2,rewardtime); rewards=rewards+1; end
		beep(sM.audio,'high'); 
		fprintf('===>>> Correct given, ITI=%.2f!\n',ana.ITI);
		if ana.sendTrigger;WaitSecs(0.02);lM.strobeServer(250); end
		if ana.visualFeedback;drawGreenSpot(sM,80);end
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		vbl=flip(sM); ct = vbl;
		if drawEye==2;drawEyePositions('Correct!');end
		cloop=1;
		while vbl <= ct + ana.ITI
			if ana.visualFeedback;if cloop<60; drawGreenSpot(sM,80); end; end
			if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
			vbl=flip(sM); cloop=cloop+1;
			doBreak = checkKeys();
			if doBreak; break; end
		end
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		flip(sM);
		thisResponse = 1;
		pfeedback = pfeedback + 1;
		if ana.isVEP
			updateTask(seq,true,tEnd-tStart); %updates our current run number
			if seq.taskFinished; breakLoop = true; end
		end
	end

	function incorrect()
		beep(sM.audio,'low');
		fprintf('===>>> Incorrect given, timeout=%.2f!\n',ana.timeOut);
		if ana.sendTrigger;WaitSecs(0.02);lM.strobeServer(251); end
		if ana.visualFeedback;drawRedSpot(sM,80);end
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		vbl=flip(sM); ct = vbl;
		if drawEye==2; drawEyePositions('Incorrect!'); end
		cloop=1;
		while vbl <= ct + ana.timeOut
			if ana.visualFeedback;if cloop<60; drawRedSpot(sM,80); end; end
			if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
			vbl=flip(sM);cloop=cloop+1;
			doBreak = checkKeys();
			if doBreak; break; end
		end
		if ana.photoDiode; drawPhotoDiodeSquare(sM,[0 0 0]); end
		flip(sM);
		thisResponse = 0;
		nfeedback = nfeedback + 1;
	end

	function drawEyePositions(intext)
		if ~isempty(eT.xAll) && ~isempty(eT.yAll) && (length(eT.xAll)==length(eT.yAll))
			xy = [eT.xAll;eT.yAll];
			drawDots(s,xy,8,[0.25 1 0 0.2]);
			drawGrid(s);
			if exist('intext','var') && ~isempty(intext); drawText(s,intext); end
			drawScreenCenter(s);
			flip(s,[],[],2);
		end
	end

end
