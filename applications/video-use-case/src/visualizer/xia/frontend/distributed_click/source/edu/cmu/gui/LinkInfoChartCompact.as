﻿package edu.cmu.gui {		import flash.display.MovieClip;	import flash.display.Shape;	import flash.utils.Dictionary;	import flash.text.TextFormat;	import flash.text.TextField;	import flash.text.TextFieldAutoSize;	import edu.cmu.MyGlobal;	//[Embed(source='Arial.ttf', fontName='fontArial', mimeType='application/x-font')]		public class LinkInfoChartCompact extends LinkInfoChart {				// Constants:								// Initialization:		public function LinkInfoChartCompact() {			WIDTH = 60;			HEIGHT = 45;			N = 20; // how many previous points to remember			FOREGROUND_COLOR = 0x444444;  // color for axes and text			PLOT_AREA_COLOR = 0xFFFFFF;			PADDING_BOTTOM = 5;  // space between X axis and bottom of box			PADDING_LEFT = 5;  // space between Y axis and left of box			PADDING_TOP = 5;			PADDING_RIGHT = 5;			DRAW_AXES = false;						super();		}		// Public Methods:			}}