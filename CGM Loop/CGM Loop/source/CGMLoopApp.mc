//
// Copyright 2016 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

using Toybox.Application as App;

class CGMLoop extends App.AppBase
{
	var myView;
	var timer;
	var timerStarted = false;
	
    function initialize() {
        AppBase.initialize();
        timer = new Timer.Timer();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }
    
    function startTimer() {
    	if (!timerStarted) {
    		timer.start(method(:refreshUI), 10000, true);
    		timerStarted = true;
		}
    }

    function refreshUI() {
    	myView.updateView();
    }

    function onSettingsChanged() {
    	myView.updateView();
    }

    function getInitialView() {
    	myView = new CGMLoopView();
        return [ myView ];
    }

    function getGoalView(goal){
        return [new CGMLoopGoalView(goal)];
    }
}
