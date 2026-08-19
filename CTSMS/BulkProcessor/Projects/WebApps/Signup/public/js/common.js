
//https://connect.microsoft.com/IE/feedback/details/807447/ie-11-metro-version-submitting-form-fails-if-input-tag-has-no-name-attribute
//if (!window.console) console = {log: function() {}};

var datePickerDefaults = $.extend( true, {}, $.datepicker.regional[context.lang] );
datePickerDefaults.dateFormat = context.dateFormat.replace('yyyy','yy').replace('MM','mm');

datePickerDefaults.changeMonth = true;
datePickerDefaults.changeYear = true;
$.datepicker.setDefaults(datePickerDefaults);
var timePickerDefaults = $.extend( true, {}, $.fgtimepicker.regional[context.lang] );
timePickerDefaults.timeSeparator = ':';
timePickerDefaults.showPeriodLabels = false;
$.fgtimepicker.setDefaults(timePickerDefaults);

var INPUT_DATE_PATTERN = context.dateFormat;
var INPUT_TIME_PATTERN = 'HH' + timePickerDefaults.timeSeparator + 'mm';
var VO_TIME_PATTERN = 'HH' + timePickerDefaults.timeSeparator + 'mm' + timePickerDefaults.timeSeparator + 'ss';
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
		var sessionExpiry = (new Date());
        sessionExpiry.setSeconds(sessionExpiry.getSeconds() + sessionMaxInactiveInterval);
		jQuery('#session_timer').countdown(sessionExpiry, {
		    elapse : false, // Allow to continue after finishes
		    precision : 1000, // The update rate in milliseconds
		}).on('update.countdown', function(event) {
			jQuery(this).html(event.strftime(SESSION_TIMER_PATTERN));
		}).on('finish.countdown', function(event) {
            self.location = context.uriBase;


		});
	} else {
		sessionMaxInactiveInterval = null;
	}
}

function resetSessionTimers() {
	if (sessionMaxInactiveInterval != null) {
		var sessionExpiry = (new Date());
        sessionExpiry.setSeconds(sessionExpiry.getSeconds() + sessionMaxInactiveInterval);
		jQuery('#session_timer').countdown(sessionExpiry);
	}
}

function applyRestApiJwtFromResponse(jqXHR) {
	if (jqXHR == null || typeof jqXHR.getResponseHeader !== 'function') {
		return;
	}
	var jwt = jqXHR.getResponseHeader('X-Rest-Api-Jwt');
	if (jwt == null || jwt.length === 0) {
		return;
	}
	if (typeof REST_API_JWT !== 'undefined') {
		REST_API_JWT = jwt;
	}
	if (typeof RestApi !== 'undefined' && typeof RestApi.applySessionJwt === 'function') {
		RestApi.applySessionJwt(jwt);
	}
}

$.ajaxSettings = $.extend( true, {}, $.ajaxSettings );
$.ajaxSettings.crossDomain = false;
$.ajaxSettings.type = "POST";
$.ajaxSettings.async = true;
$.ajaxSettings.dataType = 'json';
$.ajaxSettings.timeout = 60000;
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
        setMessages('error', { summary: textStatus, detail: errorThrown });
        hideWaitDlg();
    }
};
$.ajaxSettings.beforeSend = function(jqXHR, settings) {

    showWaitDlg();
};
$.ajaxSettings.complete = function(jqXHR, textStatus) {
    resetSessionTimers();
    applyRestApiJwtFromResponse(jqXHR);
};

var autoCompleteAjaxSettings = $.extend( true, {}, $.ajaxSettings );
autoCompleteAjaxSettings.crossDomain = false;
autoCompleteAjaxSettings.timeout = 15000;
autoCompleteAjaxSettings.type = "POST";
autoCompleteAjaxSettings.async = true;
autoCompleteAjaxSettings.dataType = 'json';
autoCompleteAjaxSettings.cache = true;
autoCompleteAjaxSettings.global = false;
autoCompleteAjaxSettings.error = null;
autoCompleteAjaxSettings.beforeSend = function(jqXHR, settings) {

};
autoCompleteAjaxSettings.complete = function(jqXHR, textStatus) {
    resetSessionTimers();
    applyRestApiJwtFromResponse(jqXHR);
};

var restApiAjaxSettings = $.extend( true, {}, $.ajaxSettings );
restApiAjaxSettings.crossDomain = true;
restApiAjaxSettings.timeout = 15000;
restApiAjaxSettings.type = "GET";
restApiAjaxSettings.async = true;
restApiAjaxSettings.dataType = 'json';
restApiAjaxSettings.cache = false;
restApiAjaxSettings.global = false;
restApiAjaxSettings.error = null;
restApiAjaxSettings.beforeSend = function(jqXHR, settings) {

};
restApiAjaxSettings.complete = null;

function getTitleAutoCompleteConfig() {
    return {

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/title',
                data: { title: request.query },

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

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/country',
                data: { country_name: request.query },

                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getProvinceAutoCompleteConfig(countryNameId) {
    return {

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/province',
                data: { province: request.query, country_name: $('#' + countryNameId).val() },

                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getCityNameAutoCompleteConfig(countryNameId,provinceId,zipCodeId) {
    return {

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/city',
                data: { city_name: request.query, country_name: $('#' + countryNameId).val(), province: $('#' + provinceId).val(), zip_code: $('#' + zipCodeId).val() },

                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getZipCodeAutoCompleteConfig(countryNameId,provinceId,cityNameId) {
    return {

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/zip',
                data: { zip_code: request.query, country_name: $('#' + countryNameId).val(), province: $('#' + provinceId).val(), city_name: $('#' + cityNameId).val() },

                context: this,
                success: function(data) {
                    response.call(this, data);
                }
            }));
        }
    };
}

function getStreetNameAutoCompleteConfig(countryNameId,provinceId,cityNameId) {
    return {

        effect: 'fade',
        effectSpeed: 'fast',
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/street',
                data: { street_name: request.query, country_name: $('#' + countryNameId).val(), province: $('#' + provinceId).val(), city_name: $('#' + cityNameId).val() },

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

        effect: 'fade',
        effectSpeed: 'fast',
        forceSelection: inputField.strict,
        dropdown: inputField.strict,
        completeSource: function(request, response) {
            $.ajax($.extend( true, {}, autoCompleteAjaxSettings, {

                url: context.uriBase + '/autocomplete/fieldvalue',
                data: { value: request.query, id: inputField.id },

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

function initMainPrimeUI(context) {

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
        width: 'auto',
        modal: true,
        closeOnEscape: false,
        closable: false,
        minimizable: false,
        maximizable: false

    });
}

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


}

function delay(callback, ms) {
    var timer = 0;
    return function() {
        var context = this, args = arguments;
        clearTimeout(timer);
        timer = setTimeout(function () {
            callback.apply(context, args);
        }, ms || 0);
    };
}

var AUTOFILL_SKIP_TYPES = {
    hidden : true,
    submit : true,
    button : true,
    checkbox : true,
    radio : true,
    file : true,
    image : true,
    reset : true
};

var AUTOFILL_READONLY_TYPES = {
    text : true,
    email : true,
    tel : true,
    search : true,
    url : true,
    password : true,
    number : true,
    date : true,
    datetime : true,
    'datetime-local' : true,
    month : true,
    week : true,
    time : true
};

function disableBrowserAutofill(root, reinit) {
    var $root = root ? jQuery(root) : jQuery(document);
    $root.find('form').attr('autocomplete', 'off');
    $root.find('input, textarea, select').each(function() {
        var el = this;
        var $el = jQuery(el);
        var tag = (el.tagName || '').toLowerCase();
        var type = (el.type || '').toLowerCase();
        if (tag === 'input' && AUTOFILL_SKIP_TYPES[type]) {
            return;
        }
        $el.attr('autocomplete', 'ctsms-off');
        var useReadonly = tag === 'textarea'
                || (tag === 'input' && (!type || AUTOFILL_READONLY_TYPES[type]));
        if (!useReadonly) {
            return;
        }
        var bindUnlock = function($field) {
            $field.off('focus.ctsmsAutofill mousedown.ctsmsAutofill')
                .on('mousedown.ctsmsAutofill focus.ctsmsAutofill', function() {
                    jQuery(this)
                        .prop('readonly', false)
                        .removeData('ctsmsAutofillGuard')
                        .data('ctsmsAutofillUnlocked', true)
                        .off('focus.ctsmsAutofill mousedown.ctsmsAutofill');
                });
        };
        if (reinit) {
            $el.removeData('ctsmsAutofillUnlocked');
            $el.off('focus.ctsmsAutofill mousedown.ctsmsAutofill');
            // Keep the guard when we still own readonly: a later reinit used to
            // drop the unlock handler and then skip rebinding because the field
            // was already readonly (inquiry datagrid inits one field at a time).
            if ($el.data('ctsmsAutofillGuard') && $el.prop('readonly')) {
                if ($el[0] === document.activeElement) {
                    $el.prop('readonly', false)
                        .removeData('ctsmsAutofillGuard')
                        .data('ctsmsAutofillUnlocked', true);
                    return;
                }
                bindUnlock($el);
                return;
            }
            $el.removeData('ctsmsAutofillGuard');
        }
        // User already unlocked this field; keep editable across AJAX (e.g. autocomplete).
        if ($el.data('ctsmsAutofillUnlocked')) {
            return;
        }
        // Stale guard: marked protected but editable again without unlock (reused/reinit).
        if ($el.data('ctsmsAutofillGuard') && !$el.prop('readonly')) {
            $el.removeData('ctsmsAutofillGuard');
            $el.off('focus.ctsmsAutofill mousedown.ctsmsAutofill');
        }
        if ($el.data('ctsmsAutofillGuard')) {
            return;
        }
        $el.data('ctsmsAutofillGuard', true);
        if ($el[0] === document.activeElement) {
            $el.prop('readonly', false)
                .removeData('ctsmsAutofillGuard')
                .data('ctsmsAutofillUnlocked', true);
            return;
        }
        if (!$el.prop('readonly')) {
            $el.prop('readonly', true);
            bindUnlock($el);
        } else {
            $el.removeData('ctsmsAutofillGuard');
        }
    });
}

jQuery(function() {
    disableBrowserAutofill();
});
jQuery(document).ajaxComplete(function() {
    disableBrowserAutofill();
});