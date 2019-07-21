
//https://connect.microsoft.com/IE/feedback/details/807447/ie-11-metro-version-submitting-form-fails-if-input-tag-has-no-name-attribute
//if (!window.console) console = {log: function() {}};

var datePickerDefaults = $.extend( true, {}, $.datepicker.regional[context.lang] );
datePickerDefaults.dateFormat = context.dateFormat.replace('yyyy','yy').replace('MM','mm'); // yyyy-MM-dd -> yy-mm-dd
//datePickerDefaults.yearRange: "-120:+0",
datePickerDefaults.changeMonth = true;
datePickerDefaults.changeYear = true;
$.datepicker.setDefaults(datePickerDefaults);
var timePickerDefaults = $.extend( true, {}, $.fgtimepicker.regional[context.lang] );
timePickerDefaults.timeSeparator = ':';
timePickerDefaults.showPeriodLabels = false;
$.fgtimepicker.setDefaults(timePickerDefaults);

var INPUT_DATE_PATTERN = context.dateFormat;
var INPUT_TIME_PATTERN = 'HH' + timePickerDefaults.timeSeparator + 'mm';
var INPUT_DATETIME_PATTERN = INPUT_DATE_PATTERN + ' ' + INPUT_TIME_PATTERN;
var INPUT_DECIMAL_SEPARATOR = context.decimalSeparator;
var INPUT_TIMEZONE_ID = context.inputTimezone;
var SYSTEM_TIMEZONE_ID = context.systemTimezone;

var waitDialogShown = false;
function showWaitDlg() {
    if (!waitDialogShown) {
        $('#wait_dlg').puidialog('show');
        waitDialogShown = true;
    }
}
function hideWaitDlg() {
    if (waitDialogShown) {
        $('#wait_dlg').puidialog('hide');
        waitDialogShown = false;
    }
}

var sessionMaxInactiveInterval = null;
function createSessionTimer(duration) {
	if (duration != null && duration > 0) {
		sessionMaxInactiveInterval = +duration;
		var sessionExpiry = (new Date()); //.addSeconds(sessionMaxInactiveInterval);
        sessionExpiry.setSeconds(sessionExpiry.getSeconds() + sessionMaxInactiveInterval);
		jQuery('#session_timer').countdown(sessionExpiry, { //.toString('yyyy/MM/dd HH:mm:ss'), {
		    elapse : false, // Allow to continue after finishes
		    precision : 1000, // The update rate in milliseconds
		}).on('update.countdown', function(event) {
			jQuery(this).html(event.strftime(SESSION_TIMER_PATTERN));
		}).on('finish.countdown', function(event) {
            self.location = context.uriBase;
			//sessionMaxInactiveInterval = null;
			//jQuery(this).html('XXXX'); //SESSION_EXPIRED_MESSAGE);
		});
	} else {
		sessionMaxInactiveInterval = null;
	}
}

function resetSessionTimers() {
	if (sessionMaxInactiveInterval != null) {
		var sessionExpiry = (new Date()); //.addSeconds(sessionMaxInactiveInterval);
        sessionExpiry.setSeconds(sessionExpiry.getSeconds() + sessionMaxInactiveInterval);
		jQuery('#session_timer').countdown(sessionExpiry); //.toString('yyyy/MM/dd HH:mm:ss'));
	}
}

//$.support.cors = true;

$.ajaxSettings = $.extend( true, {}, $.ajaxSettings );
$.ajaxSettings.crossDomain = false;
$.ajaxSettings.type = "POST";
$.ajaxSettings.async = true;
$.ajaxSettings.dataType = 'json';
$.ajaxSettings.timeout = 60000; //15000; //60000;
$.ajaxSettings.global = false;
$.ajaxSettings.cache = false;
$.ajaxSettings.error = function(jqXHR, textStatus, errorThrown) {
    if (404 == jqXHR.status) {
        if (jqXHR.responseJSON.msgs != null) {
            setMessages('warn', jqXHR.responseJSON.msgs );
        } else {
            setMessages('error', { summary: textStatus, detail: errorThrown });
        }
        if (jqXHR.responseJSON.forward != null) {
            self.location = jqXHR.responseJSON.forward;
        } else {
            hideWaitDlg();
        }
    } else {
        setMessages('error', { summary: textStatus, detail: errorThrown }); //{summary: 'Message Title', detail: context.apiError});
        hideWaitDlg();
    }
};
$.ajaxSettings.beforeSend = function(jqXHR, settings) {
    //jqXHR.setRequestHeader('Connection', 'close');
    showWaitDlg();
};
$.ajaxSettings.complete = function(jqXHR, textStatus) {
    resetSessionTimers();
};

var autoCompleteAjaxSettings = $.extend( true, {}, $.ajaxSettings );
autoCompleteAjaxSettings.crossDomain = false;
autoCompleteAjaxSettings.timeout = 15000; //5000;
autoCompleteAjaxSettings.type = "POST";
autoCompleteAjaxSettings.async = true;
autoCompleteAjaxSettings.dataType = 'json';
autoCompleteAjaxSettings.cache = true;
autoCompleteAjaxSettings.global = false;
autoCompleteAjaxSettings.error = null;
autoCompleteAjaxSettings.beforeSend = function(jqXHR, settings) {
    //jqXHR.setRequestHeader('Connection', 'close');
};
autoCompleteAjaxSettings.complete = function(jqXHR, textStatus) {
    resetSessionTimers();
};

var restApiAjaxSettings = $.extend( true, {}, $.ajaxSettings );
restApiAjaxSettings.crossDomain = true;
restApiAjaxSettings.timeout = 15000; //15000;
restApiAjaxSettings.type = "GET";
restApiAjaxSettings.async = true;
restApiAjaxSettings.dataType = 'json';
restApiAjaxSettings.cache = false;
restApiAjaxSettings.global = false;
restApiAjaxSettings.error = null;
restApiAjaxSettings.beforeSend = function(jqXHR, settings) {
    //jqXHR.setRequestHeader('Connection', 'close');
};
restApiAjaxSettings.complete = null;

function getTitleAutoCompleteConfig() {
    return {
        //styleClass: 'ctsms-control-smaller',
        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                // "GET",
                url: context.uriBase + '/autocomplete/title',
                data: { title: request.query },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getCountryNameAutoCompleteConfig() {
    return {
        //styleClass: 'ctsms-control',
        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                //type: "GET",
                url: context.uriBase + '/autocomplete/country',
                data: { country_name: request.query },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getCityNameAutoCompleteConfig(countryNameId,zipCodeId) {
    return {
        //styleClass: 'ctsms-control',
        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                //type: "GET",
                url: context.uriBase + '/autocomplete/city',
                data: { city_name: request.query, country_name: $('#' + countryNameId).val(), zip_code: $('#' + zipCodeId).val() },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getZipCodeAutoCompleteConfig(countryNameId,cityNameId) {
    return {
        //styleClass: 'ctsms-control-smaller',
        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                //type: "GET",
                url: context.uriBase + '/autocomplete/zip',
                data: { zip_code: request.query, country_name: $('#' + countryNameId).val(), city_name: $('#' + cityNameId).val() },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getStreetNameAutoCompleteConfig(countryNameId,cityNameId) {
    return {
        //styleClass: 'ctsms-control',
        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                //type: "GET",
                url: context.uriBase + '/autocomplete/street',
                data: { street_name: request.query, country_name: $('#' + countryNameId).val(), city_name: $('#' + cityNameId).val() },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        },
        delay: 600
    };
}

function getFieldValueAutoCompleteConfig(inputField) {
    return {
        //styleClass: 'ctsms-control',
        effect: 'fade',
        effectSpeed: 'fast',
        forceSelection: inputField.strict,
        dropdown: inputField.strict,
        completeSource: function(request, response) {
            $.ajax($.extend( true, autoCompleteAjaxSettings, {
                //type: "GET",
                url: context.uriBase + '/autocomplete/fieldvalue',
                data: { value: request.query, id: inputField.id },
                //dataType: "json",
                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getUrlPath() {
    return [location.protocol, '//', location.host, location.pathname].join('');
}

function dateIsoToUi(isoDate) {
    if (isoDate != null && isoDate.length > 0) {
        var date = isoDate.split(' ',2)[0].split('-',3);
        return zeroFill(date[2],2) + '.' + zeroFill(date[1],2) + '.' + zeroFill(date[0],4);
    } else {
        return '';
    }
}
function dateUiToIso(uiDate) {
    if (uiDate != null && uiDate.length > 0) {
        var date = isoDate.split('.',3);
        return zeroFill(date[2],4) + '-' + zeroFill(date[1],2) + '-' + zeroFill(date[0],2);
    } else {
        return null;
    }
}

function timeIsoToUi(isoTime) {
    if (isoTime != null && isoTime.length > 0) {
        var time = isoTime.split(' ',2)[1].split(':',3);
        return zeroFill(time[0],2) + ':' + zeroFill(time[1],2);
    } else {
        return '';
    }
}
function timeUiToIso(uiTime) {
    if (uiTime != null && uiTime.length > 0) {
        var time = uiTime.split(':',2);
        return '1970-01-01 ' + zeroFill(time[0],2) + ':' + zeroFill(date[1],2) + ':00';
    } else {
        return null;
    }
}

function datetimeIsoToUi(isoDatetime) {
    if (isoDatetime != null && isoDatetime.length > 0) {
        var datetime = isoTime.split(' ',2);
        var date = datetime[0].split('-',3);
        var time = datetime[1].split(':',3);
        return [ zeroFill(date[2],2) + '.' + zeroFill(date[1],2) + '.' + zeroFill(date[0],4), zeroFill(time[0],2) + ':' + zeroFill(time[1],2) ];
    } else {
        return [ '', '' ];
    }
}
function datetimeUiToIso(uiDate,uiTime) {
    if (uiDate != null && uiDate.length > 0 && uiTime != null && uiTime.length > 0) {
        var datetime = uiDatetime.split(' ',2);
        var date = uiDate.split('.',3);
        var time = uiTime.split(':',2);
        return zeroFill(date[2],4) + '-' + zeroFill(date[1],2) + '-' + zeroFill(date[0],2) + ' ' + zeroFill(time[0],2) + ':' + zeroFill(date[1],2) + ':00';
    } else {
        return null;
    }
}

function zeroFill(integer,digits) {
    var result;
    var numberOfZeroes;
    if (integer == null || (integer + '').length == 0) {
        result = '';
        numberOfZeroes = digits;
    } else {
        result = integer + '';
        numberOfZeroes = digits - (integer + '').length;
    }
    for (var i = 0; i < numberOfZeroes; i++) {
        result = '0' + result;
    }
    return result;
}

//function parseDate(input) {
//    if (input == null || input.length == 0) {
//        return null;
//    }
//    Datepicker.parseDate()
//	//return Date.parseExact(input, context.datePickerAltFormat);
//};

function initMainPrimeUI(context) {
    //$('#lang').puidropdown({
    //        styleClass: 'ctsms-control',
    //        change: function() {
    //            self.location = getUrlPath() + '?lang='+this.options[this.selectedIndex].value;
    //        }
    //});
    if (context.enableSessionTimer) {
        $('#session_timer_icon').show();
        createSessionTimer(context.sessionTimeout);
    } else {
        $('#session_timer_icon').hide();
    }

    $('#navigation').puibreadcrumb();

    $('#lang').puimenubar();

    $('#wait_dlg').puidialog({
        draggable: false,
        resizable: false,
        width: 'auto', //'200',
        modal: true,
        closeOnEscape: false,
        closable: false,
        minimizable: false,
        maximizable: false
        //appendTo: $(document.body)document.body
    });
}

//function enableTooltips() {
//    $(document).puitooltip();
//}

//function _sanitizeDatePicker(pickerId,altFieldId,required) {
//    var val = $('#' + pickerId).val();
//    if (val == null || val.length == 0) {
//        $('#' + altFieldId).val(null);
//        $('#' + pickerId).puidatepicker('setDate', null);
//        if (required) {
//            //alert();
//            return false;
//        }
//    }
//    //$.datepicker._updateAlternate(inst);
//    return true; // return false to cancel form action
//}

function setMessages(severity, msgs) {
    $('div[id$="message"]').puimessages('clear');
    $('#messages').puimessages('clear');
    if($.isArray(msgs)) {
        var messages = [];
        for(var i = 0; i < msgs.length; i++) {
            if ('messageId' in msgs[i]) {
                var messageId = msgs[i].messageId + '_message';
                if ($('#' + messageId).length > 0) {
                    $('#' + messageId).puimessages('show', severity, msgs[i]);
                } else {
                    messages.push(msgs[i]);
                }
            } else {
                messages.push(msgs[i]);
            }
        }
        if (messages.length > 0) {
            $('#messages').puimessages('show', severity, messages);
        }
    } else if (msgs != null) {
        $('#messages').puimessages('show', severity, msgs);
    }
}

function createIframe(id,htmlString) {

    var iframe = $('<iframe id="' + id + '" frameborder="0" style="width: 100%; height: 100%;" />');
    var html = $('<html/>').appendTo(iframe);
    var head = $('<head/>').appendTo(html);
    var body = $('<body />').appendTo(html);
    //body.html(htmlString);

    iframe.load(function(e){
        var body = $('#' + id).contents().find('body');
        body.html(htmlString);
        body.css({
            "margin": "4px",
            "font": "10pt/1.1 Arial,sans-serif",
            "cursor": "text"
        });
    });

    return iframe;

}

function initIframe(id,htmlString) {
    //$('#' + id).load(function(e){
    //    var body = $('#' + id).contents().find('body');
    //    body.css({
    //        "margin": "4px",
    //        "font": "10pt Arial,sans-serif",
    //        "cursor": "text"
    //    });
    //    body.html(htmlString);
    //});
}