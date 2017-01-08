//
// Copyright 2016 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.Math as Math;
using Toybox.System as Sys;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Calendar;
using Toybox.WatchUi as Ui;
using Toybox.Attention as Attention;

// This implements CGM Loop watch face
// Original design by tynbendad@github
class CGMLoopView extends Ui.WatchFace
{
    var font;
    var isAwake;
    var screenShape;
    var dndIcon;
	var hiMGDL = 240, lowMGDL = 70, hiMMOL=13.0, lowMMOL=4.0;
	var hiElapsed = 15, lowPumpbat = 30, lowPhonebat = 30, lowReservoir = 30;
	var mmolMgdlFactor = 18.018018;
	var requestComplete = true;

    function initialize() {
        WatchFace.initialize();
        screenShape = Sys.getDeviceSettings().screenShape;
    }

    function onLayout(dc) {
        font = Ui.loadResource(Rez.Fonts.id_font_black_diamond);
        if (Sys.getDeviceSettings() has :doNotDisturb) {
            dndIcon = Ui.loadResource(Rez.Drawables.DoNotDisturbIcon);
        } else {
            dndIcon = null;
        }
    }

    // Draw the watch hand
    // @param dc Device Context to Draw
    // @param angle Angle to draw the watch hand
    // @param length Length of the watch hand
    // @param width Width of the watch hand
    function drawHand(dc, angle, length, width) {
        // Map out the coordinates of the watch hand
        var coords = [[-(width / 2),0], [-(width / 2), -length], [width / 2, -length], [width / 2, 0]];
        var result = new [4];
        var centerX = dc.getWidth() / 2;
        var centerY = dc.getHeight() / 2;
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        // Transform the coordinates
        for (var i = 0; i < 4; i += 1) {
            var x = (coords[i][0] * cos) - (coords[i][1] * sin);
            var y = (coords[i][0] * sin) + (coords[i][1] * cos);
            result[i] = [centerX + x, centerY + y];
        }

        // Draw the polygon
        dc.fillPolygon(result);
        dc.fillPolygon(result);
    }

    // Draw the hash mark symbols on the watch
    // @param dc Device context
    function drawHashMarks(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        // Draw hashmarks differently depending on screen geometry
        if (Sys.SCREEN_SHAPE_ROUND == screenShape) {
            var sX, sY;
            var eX, eY;
            var outerRad = width / 2;
            var innerRad = outerRad - 10;
            // Loop through each 15 minute block and draw tick marks
            for (var i = Math.PI / 6; i <= 11 * Math.PI / 6; i += (Math.PI / 3)) {
                // Partially unrolled loop to draw two tickmarks in 15 minute block
                sY = outerRad + innerRad * Math.sin(i);
                eY = outerRad + outerRad * Math.sin(i);
                sX = outerRad + innerRad * Math.cos(i);
                eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
                i += Math.PI / 6;
                sY = outerRad + innerRad * Math.sin(i);
                eY = outerRad + outerRad * Math.sin(i);
                sX = outerRad + innerRad * Math.cos(i);
                eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
            }
        } else {
            //var coords = [0, width / 4, (3 * width) / 4, width];
            var coords = [0, width];
            for (var i = 0; i < coords.size(); i += 1) {
                var dx = ((width / 2.0) - coords[i]) / (height / 2.0);
                var upperX = coords[i] + (dx * 10);
                // Draw the upper hash marks
                dc.fillPolygon([[coords[i] - 1, 2], [upperX - 1, 12], [upperX + 1, 12], [coords[i] + 1, 2]]);
                // Draw the lower hash marks
                dc.fillPolygon([[coords[i] - 1, height-2], [upperX - 1, height - 12], [upperX + 1, height - 12], [coords[i] + 1, height - 2]]);
            }
        }
    }

	var bg=0, direction="", delta="Loading...", elapsedMills=0,
		loopstatus="", predicted="", loopElapsedSecs=0,  minPredict=0, maxPredict=0,
		pumpbat=-1, phonebat=-1, reservoir=-1, iob="", cob="", basal="";
	var bgAlert=false, elapsedAlert=false, loopstatusAlert=false,
		pumpbatAlert=false, phonebatAlert=false, reservoirAlert=false;
	function processAlerts() {
		bgAlert=false;
		elapsedAlert=false;
		loopstatusAlert=false;
		phonebatAlert=false;
		pumpbatAlert=false;
		reservoirAlert=false;

		if (((bg > hiMGDL) || (bg < lowMGDL)) &&
			((bg > hiMMOL) || (bg < lowMMOL))) {
			bgAlert = true;
        }
        
        var myMoment = new Time.Moment(elapsedMills / 1000);
		var elapsedMinutes = Math.floor(Time.now().subtract(myMoment).value() / 60);
        if (elapsedMinutes > hiElapsed) {
        	elapsedAlert = true;
        }

		if (!loopstatus.equals("Looping") &&
			!loopstatus.equals("Enacted")) {
			loopstatusAlert = true;
		}

        if (pumpbat < lowPumpbat) {
        	pumpbatAlert = true;
        }

        if (phonebat < lowPhonebat) {
        	phonebatAlert = true;
        }

        if (reservoir < lowReservoir) {
        	reservoirAlert = true;
        }
		
		if (!Sys.getDeviceSettings().doNotDisturb &&
			(bgAlert || loopstatusAlert)) {
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_CANARY);
	        }
            if (Attention has :vibrate) {
                var vibrateData = [
                        new Attention.VibeProfile(  25, 100 ),
                        new Attention.VibeProfile(  50, 100 ),
                        new Attention.VibeProfile(  75, 100 ),
                        new Attention.VibeProfile( 100, 100 ),
                        new Attention.VibeProfile(  75, 100 ),
                        new Attention.VibeProfile(  50, 100 ),
                        new Attention.VibeProfile(  25, 100 )
                      ];
                Attention.vibrate(vibrateData);
            }
		}
	}
	
	function onReceive(responseCode, data) {
		//System.println("in onReceive()\n");
		//System.print("response: " + responseCode.toString() + "\n");
		if (responseCode == 200) {
			//System.print(data.toString() + "\n");
			if (data.hasKey("bgnow")) {
				if (data["bgnow"].hasKey("mills")) {
			        //System.println(data["bgnow"]["mills"].toString());
			        elapsedMills = data["bgnow"]["mills"];
		        } else {
		        	elapsedMills = 0;
		        }
				if (data["bgnow"].hasKey("last")) {
		            //System.println(data["bgnow"]["last"].toString());
		            bg = data["bgnow"]["last"];
	            } else {
	            	bg = 0;
	            }
	            if (data["bgnow"].hasKey("sgvs") &&
	            	(data["bgnow"]["sgvs"].size() > 0) &&
	            	data["bgnow"]["sgvs"][0].hasKey("direction")) {
			        //System.println(data["bgnow"]["sgvs"][0]["direction"].toString());
			        direction = data["bgnow"]["sgvs"][0]["direction"].toString();
					var dirSwitch = { "SingleUp" => "^",
								 	  "DoubleUp" => "^^",
								 	  "FortyFiveUp" => "/",
								 	  "FortyFiveDown" => "\\",
								 	  "SingleDown" => "v",
								 	  "DoubleDown" => "vv",
								 	  "Flat" => "-",
								 	  "NONE" => "--" };
	        		System.println(direction);
		        	if (dirSwitch.hasKey(direction)) {
		        		direction = dirSwitch[direction];
		        		//System.println(direction);
		        	} else {
		        		direction = "?";
		        	}
		        } else {
		        	direction = "";
		        }
            }
			if (data.hasKey("delta") &&
				data["delta"].hasKey("display")) {
	            //System.println(data["delta"]["display"].toString());
	            delta = data["delta"]["display"].toString();
            } else {
	            delta = "";
            }
            if (data.hasKey("loop")) {
            	if (data["loop"].hasKey("display") &&
	            	data["loop"]["display"].hasKey("label")) {
	            	//System.println(data["loop"]["display"]["label"].toString());
    	        	loopstatus = data["loop"]["display"]["label"].toString();
	        	} else {
	        		loopstatus = "";
		        }
		        if (data["loop"].hasKey("lastPredicted") &&
		        	data["loop"]["lastPredicted"].hasKey("values") &&
		        	data["loop"]["lastPredicted"].hasKey("startDate")) {
					var numPredictions = data["loop"]["lastPredicted"]["values"].size();
            		//System.println(data["loop"]["lastPredicted"]["startDate"].toString());
					var loopTime = data["loop"]["lastPredicted"]["startDate"].toString();
					var options = { :year => loopTime.substring(0,4).toNumber(),
									:month => loopTime.substring(5,7).toNumber(),
									:day => loopTime.substring(8,10).toNumber(),
									:hour => loopTime.substring(11,13).toNumber(),
									:minute => loopTime.substring(14,16).toNumber(),
									:second => loopTime.substring(17,19).toNumber() };
					var moment = Calendar.moment(options);
					//var clockTime = System.getClockTime();
					//System.println("timezoneoffset=" + clockTime.timeZoneOffset.toString());
					//var offset = new Time.Duration(clockTime.timeZoneOffset*-1);
					////moment = moment.add(offset);
					//System.println(moment.value().toString());
					////var date = Calendar.info(moment, 0);
					//var date = Calendar.utcInfo(moment, 0);
					//System.println(format("$1$-$2$-$3$T$4$:$5$:$6$",
					//				[
					//				date.year,
					//				date.month.format("%02d"),
					//				date.day.format("%02d"),
					//				date.hour.format("%02d"),
					//				date.min.format("%02d"),
					//				date.sec.format("%02d")]
					//			   ));
					loopElapsedSecs = moment.value();
					//System.println(Time.now().value().toString());
					if (numPredictions > 0) {
		            	//System.println(data["loop"]["lastPredicted"]["values"][numPredictions-1].toString());
			            //System.println(data["loop"]["lastPredicted"]["values"][0].toString());
			            predicted = "->" + data["loop"]["lastPredicted"]["values"][numPredictions-1].toString();
			            minPredict = data["loop"]["lastPredicted"]["values"][numPredictions-1].toNumber();
			            maxPredict = minPredict;
			            for (var i=0; i < numPredictions; i++) {
			        		var myNum = data["loop"]["lastPredicted"]["values"][i].toNumber();
			            	if (myNum < minPredict) {
				        		minPredict = myNum;
			        		}
			            	if (myNum > maxPredict) {
				        		maxPredict = myNum;
			        		}
			            }
		        	}
		            //System.println(minPredict);
		            //System.println(maxPredict);
	            } else {
	            	loopElapsedSecs = 0;
	            	predicted = "";
	            	minPredict = 0;
	            	maxPredict = 0;
	            }
            } else {
        		loopstatus = "";
            	loopElapsedSecs = 0;
            	predicted = "";
            	minPredict = 0;
            	maxPredict = 0;
            }

			if (data.hasKey("basal") &&
				data["basal"].hasKey("display")) {
	            //System.println(data["basal"]["display"].toString());
            	basal = data["basal"]["display"].toString();
            	if (basal.toString().find("T: ") == 0) {
            		basal = "T:" + basal.toString().substring(3, basal.toString().length());
            	}
            	if (basal.toString().find("0U") != null) {
            		basal = basal.toString().substring(0, basal.toString().find("0U")) + "U";
            	}
            	if (basal.toString().find("0U") != null) {
            		basal = basal.toString().substring(0, basal.toString().find("0U")) + "U";
            	}
        	} else {
        		basal = "";
        	}
			if (data.hasKey("iob") &&
				data["iob"].hasKey("display")) {
	            //System.println(data["iob"]["display"].toString());
	            iob = data["iob"]["display"].toString() + "U";
            } else {
            	iob = "";
            }
			if (data.hasKey("cob") &&
				data["cob"].hasKey("display")) {
	            //System.println(data["cob"]["display"].toString());
	            cob = data["cob"]["display"].toNumber().toString() + "g";
            } else {
            	cob = "";
            }
            //System.println(Time.now().toString());
            if (data.hasKey("pump") &&
            	data["pump"].hasKey("data")) {
            	if (data["pump"]["data"].hasKey("battery") &&
            		(data["pump"]["data"]["battery"] != null) &&
            		data["pump"]["data"]["battery"].hasKey("value")) {
		            //System.println(data["pump"]["data"]["battery"]["value"].toString());
		            pumpbat = data["pump"]["data"]["battery"]["value"];
	            } else {
	            	pumpbat = -1;
	            }
            	//if (data["pump"]["data"].hasKey("clock") &&
            	//	(data["pump"]["data"]["clock"] != null) &&
            	//	data["pump"]["data"]["clock"].hasKey("display")) {
		        //    //System.println(data["pump"]["data"]["clock"]["display"].toString());
		        //    pumpelapsed = data["pump"]["data"]["clock"]["display"].toString();
	            //} else {
        	    //	pumpelapsed = "";
	            //}
            	if (data["pump"]["data"].hasKey("reservoir") &&
            		(data["pump"]["data"]["reservoir"] != null) &&
            		data["pump"]["data"]["reservoir"].hasKey("value")) {
                    //System.println(data["pump"]["data"]["reservoir"]["value"].toString());
        		    reservoir = data["pump"]["data"]["reservoir"]["value"];
	            } else {
	            	reservoir = -1;
	            }
            } else {
            	pumpbat = -1;
            	//pumpelapsed = "";
            	reservoir = -1;
            }
            if (data.hasKey("pump") &&
            	data["pump"].hasKey("uploader") &&
            	(data["pump"]["uploader"] != null) &&
            	data["pump"]["uploader"].hasKey("battery")) {
	            //System.println(data["pump"]["uploader"]["battery"].toString());
	            phonebat = data["pump"]["uploader"]["battery"];
            } else {
            	phonebat = -1;
            }
            
       		if (((elapsedMills / 1000.0) < (loopElapsedSecs - 300)) &&
       			(bg != data["loop"]["lastPredicted"]["values"][0])) {
       			bg = data["loop"]["lastPredicted"]["values"][0];
       			delta = "";
       			direction = "";
       			//System.println(elapsedMills.toString());
       			//System.println(loopElapsedSecs.toString());
       			elapsedMills = loopElapsedSecs * 1000.0;
       			//System.println(elapsedMills.toString());
			} 
		} else {
			System.println("onRecieve error");
			System.print("response: " + responseCode.toString() + "\n");
		}
		requestComplete = true;
        Ui.requestUpdate();
        processAlerts();
	}
	
    static var savedMin = 0;

    // Handle the update event
    function onUpdate(dc) {
        var width;
        var height;
        var screenWidth = dc.getWidth();
        var clockTime = Sys.getClockTime();
        var hourHand;
        var minuteHand;
        var secondHand;
        var secondTail;
		var stats = Sys.getSystemStats();

        width = dc.getWidth();
        height = dc.getHeight();
		//System.println("W: " + width.toString() + ", H: " + height.toString());
		
        var now = Time.now();
        var info = Calendar.info(now, Time.FORMAT_LONG);

        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);
        var hourStr = Lang.format("$1$", [(clockTime.hour % 12) ? clockTime.hour % 12 : 12]);
        var minStr = Lang.format("$1$", [clockTime.min < 10 ? "0" + clockTime.min.toString() : clockTime.min]);

        // Clear the screen
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());

        // Draw the gray rectangle
        //dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_DK_GRAY);
        dc.setColor(Gfx.COLOR_DK_BLUE, Gfx.COLOR_DK_BLUE);
        dc.fillPolygon([[0, 0], [dc.getWidth(), 0], [dc.getWidth(), dc.getHeight()], [0, 0]]);

        // Draw the numbers
/*
        dc.drawText((width / 2), 2, font, "12", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width - 2, (height / 2) - 15, font, "3", Gfx.TEXT_JUSTIFY_RIGHT);
        dc.drawText(width / 2, height - 30, font, "6", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(2, (height / 2) - 15, font, "9", Gfx.TEXT_JUSTIFY_LEFT);
*/
		// bg, direction, delta, elapsed
		// loopstatus, predicted
		// pumpbat, pumpelapsed, reservoir, phonebat;
        var myMoment = new Time.Moment(elapsedMills / 1000);
        //System.println(Time.now().value().toString());
        //System.println(myMoment.value().toString());
        //System.println(Time.now().subtract(myMoment).value().toString());
		var elapsedMinutes = Math.floor(Time.now().subtract(myMoment).value() / 60);
        var elapsed = elapsedMinutes.format("%d") + "m ago";
        if ((elapsedMinutes > 9999) || (elapsedMinutes < 0)) {
        	elapsed = "";
        }
	
		var lineY, edgeX, edgeY;
		var showBatteryLine, showDateLine;
		showBatteryLine = true;
		showDateLine = true;
		//System.println("shape: " + screenShape.toString());
        if (Sys.SCREEN_SHAPE_RECTANGLE != screenShape) {
        	if (height > 200) {
	        	// assumes (fenix3/bravo/etc): W: 218, H: 218
				lineY = [ 12,    // BG
						  35,    // direction,...
						  57,    // loop...
						  79,    // battery...
						  101,   // basal...
						  123,   // OB...
						  145,   // date
						  171 ]; // time
				edgeX = 34;
				edgeY = 50;
			} else {
	        	// assumes (forerunner 235/etc) W: 215, H: 180
				lineY = [ 2,     // BG
						  27,    // direction,...
						  47,    // loop...
						  67,    // battery...
						  87,    // basal...
						  107,   // OB...
						  127,   // date
						  151 ]; // time
				edgeX = 42;
				edgeY = 22;
			}
	    } else {
	    	if (height > 200) {
		    	// assumes (vivoactiveHR/etc) W: 148, H: 205
				lineY = [ 2,     // BG
						  32,    // direction,...
						  55,    // loop...
						  78,    // battery...
						  101,   // basal...
						  124,   // OB...
						  147,   // date
						  175 ]; // time
				edgeX = 2;
				edgeY = 22;
			} else {
		    	// assumes (vivoactive/920XT) W: 205, H: 148
				lineY = [ 2,     // BG
						  30,    // direction,...
						  51,    // loop...
						  0,     // N/A (battery...)
						  72,    // basal...
						  93,    // OB... or batteries if low
						  0,     // N/A (date)
						  120 ]; // time
				edgeX = 5;
				edgeY = 22;
				showBatteryLine = false;
				showDateLine = false;
			}
	    }
		if (bgAlert) {
	        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_BLACK);
		} else {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		}
		dc.drawText((width / 2), lineY[0], font, bg.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        if (minPredict > 0) {
			dc.drawText(edgeX, lineY[0], Gfx.FONT_MEDIUM, "  " + minPredict.toString(), Gfx.TEXT_JUSTIFY_LEFT);
		}
		if (maxPredict > 0) {
			dc.drawText(width - edgeX, lineY[0], Gfx.FONT_MEDIUM, maxPredict.toString() + "  ", Gfx.TEXT_JUSTIFY_RIGHT);
		}
		if (elapsedAlert) {
	        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_BLACK);
		} else {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		}
        dc.drawText(width / 2, lineY[1], Gfx.FONT_MEDIUM, direction + "  " + delta + " " + elapsed, Gfx.TEXT_JUSTIFY_CENTER);
		if (loopstatusAlert) {
	        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_BLACK);
		} else {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		}
        dc.drawText(width / 2, lineY[2], Gfx.FONT_MEDIUM, loopstatus + " " + predicted, Gfx.TEXT_JUSTIFY_CENTER);
		if (phonebatAlert || pumpbatAlert) {
	        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_BLACK);
		} else {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		}
        if (showBatteryLine && ((phonebat > -1) || (pumpbat > -1))) {
	        dc.drawText(width / 2, lineY[3], Gfx.FONT_MEDIUM, "up:" + phonebat.toString() + "% pmp:" + pumpbat.toString() + "%", Gfx.TEXT_JUSTIFY_CENTER);
        }
		if (reservoirAlert) {
	        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_BLACK);
		} else {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		}
        if (basal.length() || (reservoir > -1)) {
	        dc.drawText(width / 2, lineY[4], Gfx.FONT_MEDIUM, basal + " res:" + reservoir.toNumber().toString() + "U", Gfx.TEXT_JUSTIFY_CENTER);
	    }
        
        if ((pumpbatAlert || phonebatAlert) && !showBatteryLine) {
	        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_BLACK);
	        dc.drawText(width / 2, lineY[5], Gfx.FONT_MEDIUM, "up:" + phonebat.toString() + "% pmp:" + pumpbat.toString() + "%", Gfx.TEXT_JUSTIFY_CENTER);
        } else if ((iob.length()) || (cob.length())) {
	        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
	        dc.drawText(width / 2, lineY[5], Gfx.FONT_MEDIUM, "ob: " + iob + " " + cob, Gfx.TEXT_JUSTIFY_CENTER);
		}

        // Draw the date
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        if (showDateLine) {
        	dc.drawText(width / 2, lineY[6], Gfx.FONT_MEDIUM, dateStr, Gfx.TEXT_JUSTIFY_CENTER);
    	}
        if (stats.battery < 50.0) {
	        dc.drawText(width - edgeX, height - edgeY, Gfx.FONT_SMALL, stats.battery.toNumber().toString()+"%", Gfx.TEXT_JUSTIFY_RIGHT);
        }
        // Draw the do-not-disturb icon
        if (null != dndIcon && Sys.getDeviceSettings().doNotDisturb) {
            dc.drawBitmap( edgeX - 4, height - edgeY - 3, dndIcon);
        }
        // Draw the digital time
        dc.drawText(width / 2 - 10, lineY[7], font, hourStr, Gfx.TEXT_JUSTIFY_RIGHT);
        dc.drawText(width / 2 + 0, lineY[7], font, minStr, Gfx.TEXT_JUSTIFY_LEFT);
        dc.fillCircle(width / 2 - 5, lineY[7] + 7, 4);
        dc.fillCircle(width / 2 - 5, lineY[7] + 20, 4);

/*
        // Draw the hash marks
        drawHashMarks(dc);

        // Draw the do-not-disturb icon
        if (null != dndIcon && Sys.getDeviceSettings().doNotDisturb) {
            dc.drawBitmap( width * 0.75, height / 2 - 15, dndIcon);
        }

        // Draw the hour. Convert it to minutes and compute the angle.
        hourHand = (((clockTime.hour % 12) * 60) + clockTime.min);
        hourHand = hourHand / (12 * 60.0);
        hourHand = hourHand * Math.PI * 2;
        drawHand(dc, hourHand, 40, 3);

        // Draw the minute
        minuteHand = (clockTime.min / 60.0) * Math.PI * 2;
        drawHand(dc, minuteHand, 70, 2);

        // Draw the second
        if (isAwake) {
            dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            secondHand = (clockTime.sec / 60.0) * Math.PI * 2;
            secondTail = secondHand - Math.PI;
            drawHand(dc, secondHand, 60, 2);
            drawHand(dc, secondTail, 20, 2);
        }

        // Draw the arbor
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_BLACK);
        dc.fillCircle(width / 2, height / 2, 5);
        dc.setColor(Gfx.COLOR_BLACK,Gfx.COLOR_BLACK);
        dc.drawCircle(width / 2, height / 2, 5);
*/
        
        if ((clockTime.min != savedMin) && requestComplete && elapsedMinutes >= 5) {
        	//System.print(clockTime.min.toString() + "\n");
			var url = Application.getApp().getProperty("nsurl");
			if (url) {
				System.println("url: " + url.toString());
				url = url + "/api/v2/properties/basal,bgnow,iob,cob,loop,pump,delta";
	        	requestComplete = false;
	        	Communications.makeWebRequest(url, {"format" => "json"}, {}, method(:onReceive));
	//            {
	//                "Content-Type" => Comm.REQUEST_CONTENT_TYPE_URL_ENCODED
	//            },
	        }
	        savedMin = clockTime.min;
        }

        Application.getApp().startTimer();        
    }

	function updateView() {
		Ui.requestUpdate();
	}

    function onEnterSleep() {
        isAwake = false;
        Ui.requestUpdate();
    }

    function onExitSleep() {
        isAwake = true;
    }
}
