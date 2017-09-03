
var idRegexp = /^(\d+)_(\d+_)?([a-z_]+)$/;

//function _setInit(context,init) {
//    context.init = init;
//    $('#init').val(init ? 'true' : 'false');
//}

function initPrimeUI(context) {
    
    context.fieldsPerPage = 5;
    context.fieldsPerRow = 1; //3;
    
    //_setInit(context,true);
    context.init = true;
    context.checkForm = null;
    
    context.cs = new CommentStripper();
    
    $('#messages').puimessages();
    
    $("#inquiries").puidatagrid({
        header: context.inquiriesGridHeader,
        paginator: {
            rows: context.fieldsPerPage,
            page: +context.inquiryPage
        },
        lazy: true,
        columns: 1,
        datasource: function(callback, ui, updateUi) {
            _saveEnteredData(context,this,callback,ui,updateUi);
            //_saveEnteredData(context,,this);
        },
        content: function(value) {
            context.inquiryStatusVar.i += 1;
            context.inquiryStatusVar.first = (context.inquiryStatusVar.i == 1);
            context.inquiryStatusVar.last = (context.inquiryStatusVar.i == context.inquiryStatusVar.rows);
            if (value._posted) {
                context.inquiryStatusVar.posted += 1;
            }
            context.inquiryStatusVar.toPost = context.inquiryStatusVar.i - context.inquiryStatusVar.posted;
            var jsValueExpression = context.cs.strip(value.inquiry.jsValueExpression);
            var jsOutputExpression = context.cs.strip(value.inquiry.jsOutputExpression);
            value.hasJsVar = value.inquiry.jsVariableName != null && value.inquiry.jsVariableName.length > 0;
            value.hasJsValueExpression = jsValueExpression != null && jsValueExpression.length > 0;
            value.hasJsOutputExpression = jsOutputExpression != null && jsOutputExpression.length > 0;
            if (context.inquiryStatusVar.first) {
                context.inquiryStatusVar.category = value.inquiry.category;
            }
            var content = [];
            var categoryPanel = _addInquiryField(context,value);
            if (categoryPanel != null) {
                content.push(categoryPanel);
            }
            if (context.inquiryStatusVar.last) {
                content.push(_createInquiryCategory(context));
            }
            return content.length > 0 ? content : null;
        },
        initContent: function(content) {
            //var categoryPanel = content[0];
            //categoryPanel.find('[id$="checkbox"]').puicheckbox();
            //categoryPanel.find('[id$="select_one_dropdown"]').puidropdown({
            //    styleClass: 'ctsms-control'
            //});
            while(context.inquiryStatusVar.fieldsToInit.length > 0) {
                var inquiryField = context.inquiryStatusVar.fieldsToInit.shift();
                _initInquiryField(context,inquiryField.value,inquiryField.content);
            }
          
            //for (var i = 0; i < context.inquiryStatusVar.categoryFields.length; i++) {
            //    var inquiryField = context.inquiryStatusVar.categoryFields[i];
            //    _initInquiryField(context,inquiryField.value,inquiryField.content);
            //}
            
            //console.log(context.inquiryStatusVar.category);
            //for (var i = 0; i < context.inquiryStatusVar.categoryFields.lengh; i++) {
            //    
            //}
    //            var selectOneDropdown = $('<input type="select" name="' + selectOneDropdownName + '" id="' + selectOneDropdownId + '"/>').puidropdown({
    //    styleClass: 'ctsms-control'
    //});
            //content.each(function(index,element){
            //    var inquiryId = _getInquiryId(element);
            //    //setCheckboxVal(inquiryId,getCheckboxVal(inquiryId));
            //});
            //$('#form :input[id*="checkbox_"]').puicheckbox();
        }
    });
    
    $('#incomplete_dlg').puidialog({
        draggable: false,
        resizable: false,
        width: 'auto', //'200',
        modal: true,
        closeOnEscape: false,
        closable: false,
        minimizable: false,
        maximizable: false,
        //appendTo: $(document.body)document.body
        buttons: [{
                text: context.yesBtnLabel,
                icon: 'fa-check',
                click: function() {
                    $('#incomplete_dlg').puidialog('hide');
                    context.checkForm = false;
                    $('#form').submit();
                }
            },
            {
                text: context.noBtnLabel,
                icon: 'fa-close',
                click: function() {
                    $('#incomplete_dlg').puidialog('hide');
                }
            }
        ]
    });    

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });
    _updateInquiryPbar(context); 
    $('#inquiryform_blank_btn').puibutton({
        icon: 'fa-file-pdf-o',
        click: function(event) {
            showWaitDlg();
            window.open(context.uriBase + '/inquiry/pdf?blank=1', '_blank');
            hideWaitDlg();
        }
    });
    $('#prev_btn').puibutton({
        icon: 'fa-angle-left'
        //iconPos: 'right'   
    });        
    $('#done_btn').puibutton({
        icon: 'fa-angle-double-right',
        iconPos: 'right'   
    });    
    $('#save_next_btn').puibutton({
        icon: 'fa-angle-right',
        iconPos: 'right',   
        click: function(event) {
            context.checkForm = true;
        }        
    });    
    
    //var cb = $('<input type="checkbox" name="x" id="x" value="true"/>');
    //$('#form').append(cb);
    //cb.puicheckbox();
}

function _addInquiryField(context,value) {
    var content = null;
    if (context.inquiryStatusVar.category != value.inquiry.category) {
        content = _createInquiryCategory(context);
        context.inquiryStatusVar.category = value.inquiry.category;
        context.inquiryStatusVar.categoryFields = [];
    }
    var field = { content: _createInquiryField(context,value), value: value };
    context.inquiryStatusVar.categoryFields.push(field);

    return content;
}

function _createInquiryCategory(context) {
    var content = $('<div></div>').puipanel({
        title: context.inquiryStatusVar.category
    });
    var grid = $('<div class="ui-datagrid-content ui-datagrid-col-' + context.fieldsPerRow + '"></div>'); //ui-datagrid-content ui-widget-content
    content.append(grid);
    for (var i = 0; i < context.inquiryStatusVar.categoryFields.length; i++) {
        grid.append(context.inquiryStatusVar.categoryFields[i].content);
        context.inquiryStatusVar.fieldsToInit.push(context.inquiryStatusVar.categoryFields[i]);
        //grid.append($('<hr/>'));
    }
    return content;
}

function _createInquiryField(context,value) {
    var content = $('<div class="ctsms-form-entry"/>');
    
    var grid = $('<div class="ui-grid"/>'); //ui-grid-responsive
    var fieldSet = $('<fieldset/>').append($('<legend/>').append(document.createTextNode(value.inquiry.position + '. ' + value.inquiry.field.name))).append(grid).puifieldset({
        toggleable: true
    });
    content.append(fieldSet);
    
    var row = $('<div class="ui-grid-row"/>').appendTo(grid);
    row.append($('<div class="ui-grid-col-4" style="margin-top:4px;"/>').append($('<label class="ctsms-align-top' + (value.inquiry.optional ? '' : ' ctsms-required') + '"/>').append(document.createTextNode(value.inquiry.field.title))));
    var inputContent = $('<div class="ui-grid-col-8"/>');
    row.append(inputContent);
    
    switch (value.inquiry.field.fieldType.type) {
        case 'SINGLE_LINE_TEXT':
            //value.textValue = '""äöüÄÖÜß\'\\n\nx';
            inputContent.append(_createSingleLineText(context,value));
            break;
        case 'MULTI_LINE_TEXT':
            //value.textValue = '""äöüÄÖÜß\'\\n\nxxxx';
            inputContent.append(_createMultiLineText(context,value));
            break;
        case 'AUTOCOMPLETE':
            inputContent.append(_createAutocomplete(context,value));
            break;        
        case 'DATE':
            //value.dateValue = '19.11.2016';
            inputContent.append(_createDatePicker(context,value));
            break;
        case 'TIME':
            //value.timeValue = '12:45';
            inputContent.append(_createTimePicker(context,value));
            break;
        case 'TIMESTAMP':
            //value.timestampdateValue = '19.11.2016';
            //value.timestamptimeValue = '12:45';
            inputContent.append(_createDateTimePicker(context,value));
            break;
        case 'CHECKBOX':    
            //value.booleanValue = true;
            inputContent.append(_createCheckbox(context,value));
            break;            
        case 'SELECT_ONE_DROPDOWN':    
            //value.someValue = true;
            inputContent.append(_createSelectOneDropdown(context,value));
            break;
        case 'SELECT_ONE_RADIO_H':
            inputContent.append(_createSelectOneRadio(context,value,false));
            break;            
        case 'SELECT_ONE_RADIO_V':            
            inputContent.append(_createSelectOneRadio(context,value,true));
            break;
        case 'SELECT_MANY_H':
            inputContent.append(_createSelectMany(context,value,false));
            break;             
        case 'SELECT_MANY_V':
            inputContent.append(_createSelectMany(context,value,true));
            break;
        case 'SKETCH':
            inputContent.append(_createSketchpad(context,value));
            break;
        case 'INTEGER':
            inputContent.append(_createSpinner(context,value));
            break;
        case 'FLOAT':
            inputContent.append(_createDecimal(context,value));
            break;
        default:
            break;
    }

    var messageId = value.inquiry.id + '_message';
    grid.append($('<div class="ui-grid-col-12"><div id="' + messageId + '" /></div>'));
    
	if (value.hasJsValueExpression || value.hasJsOutputExpression) {
        var fieldOutput = $('<div id="' + _getOutputId(value) + '">');
        grid.append($('<div class="ui-grid-col-12 ctsms-inputfield-output-row"/>').append(fieldOutput));
    }
    
    if (value.inquiry.field.comment != null && value.inquiry.field.comment.length > 0) {
        var fieldComment = $('<pre class="ui-widget ctsms-multilinetext">');
        fieldComment.append(document.createTextNode(value.inquiry.field.comment));
        grid.append($('<div class="ui-grid-col-12 ctsms-inputfield-comment-row"/>').append(fieldComment));
    }

    if (value.inquiry.comment != null && value.inquiry.comment.length > 0) {
        var comment = $('<pre class="ui-widget ctsms-multilinetext">');
        comment.append(document.createTextNode(value.inquiry.comment));
        grid.append($('<div class="ui-grid-col-12 ctsms-inputfield-comment-row"/>').append(comment));
    }
    
    if (value.hasJsValueExpression && !value.inquiry.disabled) {
        var applyBtnId = value.inquiry.id + '_apply_button';
        var applyBtn = $('<button type="button" id="' + applyBtnId + '">' + context.applyCalculatedValueBtnLabel + '</button>').puibutton({
            icon: 'fa-reply'
        });
        grid.append($('<div class="ui-grid-col-12" style="text-align:right;"/>').append(applyBtn));
    }
    
    return content;
    
}

//function _getOutputId(value) {
//    return INPUT_FIELD_OUTPUT_ID_PREFIX + value.inquiry.id; // + (value.inquiry.series ? INPUT_FIELD_OUTPUT_ID_INDEX_SEPARATOR + value.index : '');
//}

function _initInquiryField(context,value,content) {

    var applyBtnId = value.inquiry.id + '_apply_button';

    switch (value.inquiry.field.fieldType.type) {
        case 'SINGLE_LINE_TEXT':
            //value.textValue = '""äöüÄÖÜß\'\\n\nx';
            _initSingleLineText(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.singleLineTextApplyCalculatedValue(value);
            });                  
            break;
        case 'MULTI_LINE_TEXT':
            _initMultiLineText(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.multiLineTextApplyCalculatedValue(value);
            });             
            break;
        case 'AUTOCOMPLETE':
            _initAutocomplete(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.autoCompleteApplyCalculatedValue(value);
            }); 
            break;
        case 'DATE':
            _initDatePicker(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.dateApplyCalculatedValue(value);
            });            
            break;
        case 'TIME':
            _initTimePicker(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.timeApplyCalculatedValue(value);
            });                        
            break;
        case 'TIMESTAMP':
            _initDateTimePicker(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.timestampApplyCalculatedValue(value);
            });            
            break;
        case 'CHECKBOX':    
            _initCheckbox(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.checkBoxApplyCalculatedValue(value);
            });            
            break;
        case 'SELECT_ONE_DROPDOWN':
            _initSelectOneDropdown(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.selectOneDropdownApplyCalculatedValue(value);
            });             
            break;
        case 'SELECT_ONE_RADIO_H':
        case 'SELECT_ONE_RADIO_V':                    
            _initSelectOneRadio(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.selectOneRadioApplyCalculatedValue(value);
            });               
            break;
        case 'SELECT_MANY_H':
        case 'SELECT_MANY_V':                    
            _initSelectMany(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.selectManyApplyCalculatedValue(value);
            });                        
            break;
        case 'SKETCH':
            var sketchpad = _initSketchpad(context,value,content);
            window[INPUT_FIELD_WIDGET_VAR_PREFIX + value.inquiry.id] = sketchpad;
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.sketchApplyCalculatedValue(value,sketchpad);
            });            
            break;
        case 'INTEGER':
            _initSpinner(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.integerApplyCalculatedValue(value);
            });
            break;            
        case 'FLOAT':
            _initDecimal(context,value,content);
            $('#' + applyBtnId).on('click', function(event) {
                FieldCalculation.floatApplyCalculatedValue(value);
            });            
            break;
        default:
            break;
    }

    var messageId = value.inquiry.id + '_message';
    $('#' + messageId).puimessages();
    
}

function _createDatePicker(context,value) {
    var datePickerName = 'date_' + value.inquiry.id;
    var datePickerId = value.inquiry.id + '_date_picker';
    var datePickerHiddenId = value.inquiry.id + '_date_picker_hidden';
    var datePickerHidden = $('<input type="hidden" name="' + datePickerName + '" id="' + datePickerHiddenId + '" value="' + (value.dateValue != null ? value.dateValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var datePicker = $('<input type="text" class="ctsms-control-date" name="' + datePickerName + '" id="' + datePickerId + '" value="' + (value.dateValue != null ? value.dateValue : '') + '"/>').puidatepicker({
        //disabled: value.inquiry.disabled
    });
    //if (value.inquiry.disabled) {
    //    datePicker.puidatepicker('disable');
    //}    
    //datePicker.puitooltip({
    //    my: 'left bottom',
    //    at: 'left top',  
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});    
    return [ datePickerHidden, datePicker ];
}
function _initDatePicker(context,value, content) {
    var datePickerId = value.inquiry.id + '_date_picker';
    if (value.inquiry.disabled) {
        $('#' + datePickerId).puidatepicker('disable');
    } else if (value.hasJsVar) {
        $('#' + datePickerId).on('change', function(event) {
            FieldCalculation.dateOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.dateOnChange(value);
        }); 
    }
    $('#' + datePickerId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    }); 
}

function setDatePickerVal(inquiryId,date) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_date_picker');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_date_picker');
    _setPickerDate(elem,date);
}

function getDatePickerVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_date_picker');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_date_picker');
    return elem.puidatepicker('getDate');
}

function _setPickerDate(elem,date) {
    if (date != null) {
        if($.type(date) === "string") {
            date = dateIsoToUi(date);
        }
        elem.puidatepicker('setDate', date);
    } else {
        elem.puidatepicker('setDate', null);
    }
}

function _createTimePicker(context,value) {
    var timePickerName = 'time_' + value.inquiry.id;
    var timePickerId = value.inquiry.id + '_time_picker';
    var timePickerHiddenId = value.inquiry.id + '_time_picker_hidden';
    var timePickerHidden = $('<input type="hidden" name="' + timePickerName + '" id="' + timePickerHiddenId + '" value="' + (value.timeValue != null ? value.timeValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var timePicker = $('<input type="text" class="ctsms-control-time" name="' + timePickerName + '" id="' + timePickerId + '" value="' + (value.timeValue != null ? value.timeValue : '') + '"/>').puitimepicker({
        //disabled: value.inquiry.disabled
    });
    //if (value.inquiry.disabled) {
    //    timePicker.puitimepicker('disable');
    //}      
    //timePicker.puitooltip({
    //    my: 'left bottom',
    //    at: 'left top',  
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});
    return [ timePickerHidden, timePicker ];
}
function _initTimePicker(context,value,content) {
    var timePickerId = value.inquiry.id + '_time_picker';
    if (value.inquiry.disabled) {
        $('#' + timePickerId).puitimepicker('disable');
    } else if (value.hasJsVar) {
        $('#' + timePickerId).on('change', function(event) {
            FieldCalculation.timeOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.timeOnChange(value);
        }); 
    }      
    $('#' + timePickerId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });
}

function setTimePickerVal(inquiryId,time) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_time_picker');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_time_picker');
    _setPickerTime(elem,time);
}

function getTimePickerVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_time_picker');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_time_picker');
    return elem.puitimepicker('getTime');
}

function _setPickerTime(elem,time) {
    if (time != null) {
        if($.type(time) === "string" && time.length > 0) {
            time = timeIsoToUi(time);
        }
        elem.puitimepicker('setTime', time);
    } else {
        elem.puitimepicker('setTime', null);
    }
}

function _createDateTimePicker(context,value) {
    var datePickerName = 'timestampdate_' + value.inquiry.id;
    var datePickerId = value.inquiry.id + '_timestampdate_picker';
    var datePickerHiddenId = value.inquiry.id + '_timestampdate_picker_hidden';
    var datePickerHidden = $('<input type="hidden" name="' + datePickerName + '" id="' + datePickerHiddenId + '" value="' + (value.timestampdateValue != null ? value.timestampdateValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var datePicker = $('<input type="text" class="ctsms-control-date" name="' + datePickerName + '" id="' + datePickerId + '" value="' + (value.timestampdateValue != null ? value.timestampdateValue : '') + '"/>').puidatepicker({
        //disabled: value.inquiry.disabled
    });
    //if (value.inquiry.disabled) {
    //    datePicker.puidatepicker('disable');
    //}        
    //datePicker.puitooltip({
    //    my: 'left bottom',
    //    at: 'left top',  
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});    
    
    var timePickerName = 'timestamptime_' + value.inquiry.id;
    var timePickerId = value.inquiry.id + '_timestamptime_picker';
    var timePickerHiddenId = value.inquiry.id + '_timestamptime_picker_hidden';
    var timePickerHidden = $('<input type="hidden" name="' + timePickerName + '" id="' + timePickerHiddenId + '" value="' + (value.timestamptimeValue != null ? value.timestamptimeValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var timePicker = $('<input type="text" class="ctsms-control-time" name="' + timePickerName + '" id="' + timePickerId + '" value="' + (value.timestamptimeValue != null ? value.timestamptimeValue : '') + '"/>').puitimepicker({
        //disabled: value.inquiry.disabled
    });
    //if (value.inquiry.disabled) {
    //    timePicker.puitimepicker('disable');
    //}          
    //timePicker.puitooltip({
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});
    return [ datePickerHidden, datePicker, timePickerHidden, timePicker ];
}
function _initDateTimePicker(context,value,content) {
    var datePickerId = value.inquiry.id + '_timestampdate_picker';
    if (value.inquiry.disabled) {
        $('#' + datePickerId).puidatepicker('disable');
    } else if (value.hasJsVar) {
        $('#' + datePickerId).on('change', function(event) {
            FieldCalculation.timestampOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.timestampOnChange(value);
        }); 
    }              
    $('#' + datePickerId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });
    var timePickerId = value.inquiry.id + '_timestamptime_picker';
    if (value.inquiry.disabled) {
        $('#' + timePickerId).puitimepicker('disable');
    } else if (value.hasJsVar) {
        $('#' + timePickerId).on('change', function(event) {
            FieldCalculation.timestampOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.timestampOnChange(value);
        }); 
    }      
    //timePicker.puitooltip({
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});
}

function setDateTimePickerVal(inquiryId,datetime) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_timestampdate_picker');
    //} else {
    //    elem = inquiryId[0];
    //}
    var elem = $('#' + inquiryId + '_timestampdate_picker');
    _setPickerDate(elem,datetime);
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_timestamptime_picker');
    //} else {
    //    elem = inquiryId[1];
    //}
    elem = $('#' + inquiryId + '_timestamptime_picker');
    _setPickerTime(elem,datetime);
}

function getDateTimePickerVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_timestampdate_picker');
    //} else {
    //    elem = inquiryId[0];
    //}
    var elem = $('#' + inquiryId + '_timestampdate_picker');
    var date = elem.puidatepicker('getDate');
    if (date != null) {
        //if($.type(inquiryId) === "string") {
        //    elem = $('#' + inquiryId + '_timestamptime_picker');
        //} else {
        //    elem = inquiryId[1];
        //}
        elem = $('#' + inquiryId + '_timestamptime_picker');
        var time = elem.puitimepicker('getTime');
        if (time != null) {
            return new Date(date.getFullYear(), date.getMonth(), date.getDate(), time.getHours(), time.getMinutes(), 0);
        }
    }
    return null;
}

function _createSingleLineText(context,value) {
    var singleLineTextName = 'text_' + value.inquiry.id;
    var singleLineTextId = value.inquiry.id + '_single_line_text';
    var singleLineTextHiddenId = value.inquiry.id + '_single_line_text_hidden';
    var singleLineTextHidden = $('<input>', {
        "type": "hidden",
        "name": singleLineTextName,
        "id": singleLineTextHiddenId,
        "disabled": !value.inquiry.disabled,
        "value": (value.textValue != null ? value.textValue : '')
    }); //$('<input type="hidden" name="' + singleLineTextName + '" id="' + singleLineTextHiddenId + '" value=""/>');
    //var singleLineText = $('<input type="text" class="ctsms-control" name="' + singleLineTextName + '" id="' + singleLineTextId + '"/>', { "value": value.textValue }).puiinputtext();
    var singleLineText = $('<input>', {
        "type": "text",
        "class": "ctsms-control-larger",
        "name": singleLineTextName,
        "id": singleLineTextId,
        "value": (value.textValue != null ? value.textValue : '')
    }).puiinputtext();
    //if (value.inquiry.disabled) {
    //    singleLineText.puiinputtext('disable');
    //}
    //singleLineText.puitooltip({
    //    my: 'left bottom',
    //    at: 'left top',  
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});
    return [ singleLineTextHidden, singleLineText ];
}
function _initSingleLineText(context,value,content) {
    var singleLineTextId = value.inquiry.id + '_single_line_text';
    if (value.inquiry.disabled) {
        $('#' + singleLineTextId).puiinputtext('disable');
    } else if (value.hasJsVar) {
        $('#' + singleLineTextId).on('change', function(event) {
            FieldCalculation.singleLineTextOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.singleLineTextOnChange(value);
        }); 
    }      
    $('#' + singleLineTextId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });
}

function setSingleLineTextVal(inquiryId,text) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_single_line_text');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_single_line_text');
    elem.val(text);
}

function getSingleLineTextVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_single_line_text');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_single_line_text');
    return elem.val();
}

function _createMultiLineText(context,value) {
    var multiLineTextName = 'text_' + value.inquiry.id;
    var multiLineTextId = value.inquiry.id + '_multi_line_text';
    var multiLineTextHiddenId = value.inquiry.id + '_multi_line_text_hidden';
    var multiLineTextHidden = $('<input>', {
        "type": "hidden",
        "name": multiLineTextName,
        "id": multiLineTextHiddenId,
        "disabled": !value.inquiry.disabled,
        "value": (value.textValue != null ? value.textValue : '')
    }); //$('<input type="hidden" name="' + multiLineTextName + '" id="' + multiLineTextHiddenId + '" value=""/>');
    var multiLineText = $('<textarea class="ctsms-textarea" name="' + multiLineTextName + '" id="' + multiLineTextId + '"/>');
    multiLineText.append(document.createTextNode((value.textValue != null ? value.textValue : '')));

    return [ multiLineTextHidden, multiLineText ];
}
function _initMultiLineText(context,value,content) {
    var multiLineTextId = value.inquiry.id + '_multi_line_text';
    $('#' + multiLineTextId).puiinputtextarea({
        //autoResize: true
    });
    if (value.inquiry.disabled) {
        $('#' + multiLineTextId).puiinputtextarea('disable');
    } else if (value.hasJsVar) {
        $('#' + multiLineTextId).on('change', function(event) {
            FieldCalculation.multiLineTextOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.multiLineTextOnChange(value);
        }); 
    } 
    $('#' + multiLineTextId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });
}

function setMultiLineTextVal(inquiryId,text) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_multi_line_text');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_multi_line_text');
    elem.val(text);
}

function getMultiLineTextVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_multi_line_text');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_multi_line_text');
    return elem.val();
}


function _createCheckbox(context,value) {
    var checkboxName = 'boolean_' + value.inquiry.id;
    var checkboxId = value.inquiry.id + '_checkbox';
    var checkboxHiddenId = value.inquiry.id + '_checkbox_hidden';
    var checkboxHidden = $('<input type="hidden" name="' + checkboxName + '" id="' + checkboxHiddenId + '" value="' + (value.booleanValue ? 'true' : 'false') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var checkboxDefaultHiddenId = value.inquiry.id + '_checkbox_default_hidden';
    var checkboxDefaultHidden = $('<input type="hidden" name="' + checkboxName + '" id="' + checkboxDefaultHiddenId + '" value="false"' + (value.inquiry.disabled ? ' disabled' : '') + '/>');
    //$('#form').append(checkboxHidden);
    var checkbox = $('<input type="checkbox" name="' + checkboxName + '" id="' + checkboxId + '" value="true"' + (value.booleanValue ? ' checked="checked"' : '') + '/>');
    //$('#form').append(checkbox);
    //checkbox.puicheckbox();
    //checkbox.puitooltip({
    //    content: context.probandDobTooltip
    //});
    return [ checkboxHidden, checkboxDefaultHidden, checkbox ];
}
function _initCheckbox(context,value,content) {
    var checkboxId = value.inquiry.id + '_checkbox';
    $('#' + checkboxId).puicheckbox();
    if (value.inquiry.disabled) {
        $('#' + checkboxId).puicheckbox('disable');
    } else if (value.hasJsVar) {
        $('#' + checkboxId).on('change', function(event) {
            FieldCalculation.checkBoxOnChange(value);
        });
    }   
    //works like this, but not senseful for the checkbox type:
    //$('#' + checkboxId).parent().parent().puitooltip({
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});    
}

function setCheckboxVal(inquiryId,checked) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_checkbox');
    //} else {
    //    //elem = inquiryId[0];
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_checkbox');
    if (checked) {
        elem.puicheckbox('check');
    } else {
        elem.puicheckbox('uncheck');
    }
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_checkbox_hidden');
    //} else {
    //    elem = inquiryId[1];
    //}
    //elem.attr('disabled', checked);  
}

function getCheckboxVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_checkbox');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_checkbox');
    return elem.puicheckbox('isChecked'); 
}

function _createSelectOneDropdown(context,value) {
    var selectOneDropdownName = 'selection_' + value.inquiry.id;
    var selectOneDropdownId = value.inquiry.id + '_select_one_dropdown';
    var selectionSetValuesIdMap = _getSelectionSetValuesIdMap(value.selectionValues);
    var selectOneDropdownHiddenId = value.inquiry.id + '_select_one_dropdown_hidden';
    var selectOneDropdownHidden = $('<input type="hidden" name="' + selectOneDropdownName + '" id="' + selectOneDropdownHiddenId + '" value=""' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
    var result = [ selectOneDropdownHidden ];
    var selectOneDropdown = $('<select name="' + selectOneDropdownName + '" id="' + selectOneDropdownId + '"/>');
    var option = $('<option value=""/>');
    option.append(document.createTextNode(context.noSelectionLabel));
    selectOneDropdown.append(option);
    if (value.inquiry.field.selectionSetValues != null) {
        for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
            var selectionSetValue = value.inquiry.field.selectionSetValues[i];
            if (selectionSetValue.id in selectionSetValuesIdMap) {
                var optionHiddenId = value.inquiry.id + '_' + selectionSetValue.id + '_select_one_dropdown_hidden';
                var optionHidden = $('<input type="hidden" name="' + selectOneDropdownName + '" id="' + optionHiddenId + '" value="' + selectionSetValue.id + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
                result.push(optionHidden);
            }
            option = $('<option value="' + selectionSetValue.id + '"' + (selectionSetValue.id in selectionSetValuesIdMap ? ' selected="selected"' : '') + '/>');
            option.append(document.createTextNode(selectionSetValue.name));
            selectOneDropdown.append(option);
        }
    }
    //$('#gender').parent().parent().find('.ui-inputtext').puitooltip({
    //    content: context.probandGenderTooltip
    //});
    //selectOneDropdown.puitooltip({
    //   content: context.probandDobTooltip
    //});
    result.push(selectOneDropdown);
    return result;    
}
function _initSelectOneDropdown(context,value,content) {
    var selectOneDropdownId = value.inquiry.id + '_select_one_dropdown';
    $('#' + selectOneDropdownId).puidropdown({
        styleClass: 'ctsms-control',
        //value: (value.selectionValues != null ? value.selectionValues[0].id : null)
        change: (!value.inquiry.disabled && value.hasJsVar ? function(event) {
            FieldCalculation.selectOneDropdownOnChange(value);
        } : null)
    });
    if (value.inquiry.disabled) {
        $('#' + selectOneDropdownId).puidropdown('disable');
    } //else if (value.hasJsVar) {
    //    $('#' + selectOneDropdownId).on('change', function(event) {
    //        FieldCalculation.selectOneDropdownOnChange(value);
    //    });
    //}   
    $('#' + selectOneDropdownId).parent().parent().find('.ui-inputtext').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: _getTooltipText(context,value) //context.probandGenderTooltip
    });    
}

function setSelectOneDropdownVal(inquiryId,selectionValueIds) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_select_one_dropdown');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_select_one_dropdown');
    if (selectionValueIds != null && selectionValueIds.length > 0) {
        for (var i = 0; i < selectionValueIds.length; i++) {
            //$('#' + inquiryId + '_' + selectionValueIds[i] + '_select_one_radio').puiradiobutton('check');
            //return;
            elem.puidropdown('selectValue',selectionValueIds[i]);
            //return
        }
    } else {
        elem.puidropdown('selectValue','');
    }
}

function getSelectOneDropdownVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_select_one_dropdown');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_select_one_dropdown');
    var val = elem.puidropdown('getSelectedValue');
    if (val != null && val.length > 0) {
        return [ val ];
    }
    return [];
}

function _getSelectionSetValuesIdMap(selectionValues) {
    var result = {};
    if (selectionValues != null) {
        for (var i = 0; i < selectionValues.length; i++) {
            var selectionValue = selectionValues[i];
            result[selectionValue.id] = selectionValue;
        }
    }
    return result;
}

function _createSelectOneRadio(context,value,vertical) {
    var selectOneRadioName = 'selection_' + value.inquiry.id;
    var selectionSetValuesIdMap = _getSelectionSetValuesIdMap(value.selectionValues);
    var selectOneRadioHiddenId = value.inquiry.id + '_select_one_radio_hidden';
    var selectOneRadioHidden = $('<input type="hidden" name="' + selectOneRadioName + '" id="' + selectOneRadioHiddenId + '" value=""/>');
    var result = [ selectOneRadioHidden ];
    var selectOneRadioGridId = value.inquiry.id + '_select_one_radio';
    var grid = $('<div id="' + selectOneRadioGridId + '" class="ui-grid"/>'); //ui-grid-responsive //style="width:250px"
    var row = null;
    if (value.inquiry.field.selectionSetValues != null) {
        for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
            var selectionSetValue = value.inquiry.field.selectionSetValues[i];
            var radioId = value.inquiry.id + '_' + selectionSetValue.id + '_select_one_radio';

            if (selectionSetValue.id in selectionSetValuesIdMap) {
                var radioHiddenId = value.inquiry.id + '_' + selectionSetValue.id + '_select_one_radio_hidden';
                var radioHidden = $('<input type="hidden" name="' + selectOneRadioName + '" id="' + radioHiddenId + '" value="' + selectionSetValue.id + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
                result.push(radioHidden);
            }

            var radio = $('<input type="radio" name="' + selectOneRadioName + '" id="' + radioId + '" value="' + selectionSetValue.id + '"' + (selectionSetValue.id in selectionSetValuesIdMap ? ' checked="checked"' : '') + '/>');
            var label = $('<label for="' + radioId + '" class="ui-widget" />');
            label.append(document.createTextNode(selectionSetValue.name));
            if (vertical || row == null) {
                row = $('<div class="ui-grid-row" style="margin-bottom: 4px;"/>');
                grid.append(row);
            }
            $('<div class="ui-grid-col-1"/>').append(radio).appendTo(row);
            if (vertical) {
                //$('<div class="ui-grid-col-1"/>').append(selectOneRadio).appendTo(row);
                $('<div class="ui-grid-col-11" style="display:table;text-align:left;padding-top: 2px;"/>').append(label).appendTo(row);
            } else {
                $('<div class="ui-grid-col-2" style="display:table;text-align:left;padding-top: 2px;"/>').append(label).appendTo(row);
                //row.append(selectOneRadio);
                //row.append(label);
            }
        }
    }
    
    
    //$('#gender').parent().parent().find('.ui-inputtext').puitooltip({
    //    content: context.probandGenderTooltip
    //});
    //selectOneDropdown.puitooltip({
    //   content: context.probandDobTooltip
    //});
    result.push(grid);
    return result;
}
function _initSelectOneRadio(context,value,content) {
    if (value.inquiry.field.selectionSetValues != null) {
        for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
            var selectionSetValue = value.inquiry.field.selectionSetValues[i];
            var radioId = value.inquiry.id + '_' + selectionSetValue.id + '_select_one_radio';
            $('#' + radioId).puiradiobutton();
            if (value.inquiry.disabled) {
                $('#' + radioId).puiradiobutton('disable');
            } else if (value.hasJsVar) {
                $('#' + radioId).on('change', function(event) {
                    FieldCalculation.selectOneRadioOnChange(value);
                });
            }
        }
    }
    var selectOneRadioGridId = value.inquiry.id + '_select_one_radio';
    $('#' + selectOneRadioGridId).puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: _getTooltipText(context,value) //context.probandGenderTooltip
    });
    $('#' + selectOneRadioGridId).off().on('mouseenter', function(event) {
        $('#' + selectOneRadioGridId).puitooltip('show');
    }).on('mouseleave', function(event) {
        $('#' + selectOneRadioGridId).puitooltip('hide');
    }); 
    //var selectOneDropdownId = value.inquiry.id + '_select_one_dropdown';
    //$('#' + selectOneDropdownId).puidropdown({
    //    styleClass: 'ctsms-control'
    //});
    //$('#' + selectOneDropdownId).parent().parent().find('.ui-inputtext').puitooltip({
    //    content: context.probandGenderTooltip
    //});    
}
function setSelectOneRadioVal(inquiryId,selectionValueIds) {
    if (selectionValueIds != null) {
        for (var i = 0; i < selectionValueIds.length; i++) {
            $('#' + inquiryId + '_' + selectionValueIds[i] + '_select_one_radio').puiradiobutton('check');
            //return;
        }
    }
}

function getSelectOneRadioVal(inquiryId) {
    //var elems;
    //if($.type(inquiryId) === "string") {
    //    elems = $('[id^="' + inquiryId + '_"] input[type="radio"');
    //} else {
    //    elems = inquiryId;
    //}
    var elems = $('[id^="' + inquiryId + '_"] input[type="radio"');
    var result = [];
    elems.each(function(index, elem) {
        if ($(this).puiradiobutton('isChecked')) {
            //var id = elem.val();
            //result.push(+id);
            result.push($(this).val());
        }
    });
    return result; 
}

function _createSelectMany(context,value,vertical) {
    var selectManyName = 'selection_' + value.inquiry.id;
    var selectionSetValuesIdMap = _getSelectionSetValuesIdMap(value.selectionValues);
    var selectManyHiddenId = value.inquiry.id + '_select_many_hidden';
    var selectManyHidden = $('<input type="hidden" name="' + selectManyName + '" id="' + selectManyHiddenId + '" value=""/>');
    var result = [ selectManyHidden ];
    var selectManyGridId = value.inquiry.id + '_select_many';
    var grid = $('<div id="' + selectManyGridId + '" class="ui-grid"/>'); //ui-grid-responsive //style="width:250px"
    var row = null;
    if (value.inquiry.field.selectionSetValues != null) {
        for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
            var selectionSetValue = value.inquiry.field.selectionSetValues[i];
            var checkboxId = value.inquiry.id + '_' + selectionSetValue.id + '_select_many';

            if (selectionSetValue.id in selectionSetValuesIdMap) {
                var checkboxHiddenId = value.inquiry.id + '_' + selectionSetValue.id + '_select_many_hidden';
                var checkboxHidden = $('<input type="hidden" name="' + selectManyName + '" id="' + checkboxHiddenId + '" value="' + selectionSetValue.id + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');
                result.push(checkboxHidden);
            }

            var checkbox = $('<input type="checkbox" name="' + selectManyName + '" id="' + checkboxId + '" value="' + selectionSetValue.id + '"' + (selectionSetValue.id in selectionSetValuesIdMap ? ' checked="checked"' : '') + '/>');
            var label = $('<label for="' + checkboxId + '" class="ui-widget" />');
            label.append(document.createTextNode(selectionSetValue.name));
            if (vertical || row == null) {
                row = $('<div class="ui-grid-row" style="margin-bottom: 4px;"/>');
                grid.append(row);
            }
            $('<div class="ui-grid-col-1" />').append(checkbox).appendTo(row);
            if (vertical) {
                //$('<div class="ui-grid-col-1"/>').append(selectOneRadio).appendTo(row);
                $('<div class="ui-grid-col-11" style="display:table;text-align:left;padding-top: 2px;"/>').append(label).appendTo(row);
            } else {
                $('<div class="ui-grid-col-2" style="display:table;text-align:left;padding-top: 2px;"/>').append(label).appendTo(row);
                //row.append(selectOneRadio);
                //row.append(label);
            }
        }
    }
    //$('#gender').parent().parent().find('.ui-inputtext').puitooltip({
    //    content: context.probandGenderTooltip
    //});
    //selectOneDropdown.puitooltip({
    //   content: context.probandDobTooltip
    //});
    result.push(grid);
    return result;
}
function _initSelectMany(context,value,content) {
    if (value.inquiry.field.selectionSetValues != null) {
        for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
            var selectionSetValue = value.inquiry.field.selectionSetValues[i];
            var checkboxId = value.inquiry.id + '_' + selectionSetValue.id + '_select_many';
            $('#' + checkboxId).puicheckbox();
            if (value.inquiry.disabled) {
                $('#' + checkboxId).puicheckbox('disable');
            } else if (value.hasJsVar) {
                $('#' + checkboxId).on('change', function(event) {
                    FieldCalculation.selectManyOnChange(value);
                });
            }
        }
    }
    var selectManyGridId = value.inquiry.id + '_select_many';
    $('#' + selectManyGridId).puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: _getTooltipText(context,value) //context.probandGenderTooltip
    });
    $('#' + selectManyGridId).off().on('mouseenter', function(event) {
        $('#' + selectManyGridId).puitooltip('show');
    }).on('mouseleave', function(event) {
        $('#' + selectManyGridId).puitooltip('hide');
    }); 
    //var selectOneDropdownId = value.inquiry.id + '_select_one_dropdown';
    //$('#' + selectOneDropdownId).puidropdown({
    //    styleClass: 'ctsms-control'
    //});
    //$('#' + selectOneDropdownId).parent().parent().find('.ui-inputtext').puitooltip({
    //    content: context.probandGenderTooltip
    //});    
}

function setSelectManyVal(inquiryId,selectionValueIds) {
    //var elems;
    //if($.type(inquiryId) === "string") {
    //    elems = $('[id^="' + inquiryId + '_"] input[type="checkbox"');
    //} else {
    //    elems = inquiryId;
    //}
    var elems = $('[id^="' + inquiryId + '_"] input[type="checkbox"]');
    var ids = {};
    if (selectionValueIds != null) {
        for (var i = 0; i < selectionValueIds.length; i++) {
            ids[selectionValueIds[i]] = 1;
        }
    }
    elems.each(function(index, elem) {
        if ($(this).val() in ids) {
            $(this).puicheckbox('check');
        } else {
            $(this).puicheckbox('uncheck');    
        }
    });
}

function getSelectManyVal(inquiryId) {
    //var elems;
    //if($.type(inquiryId) === "string") {
    //    elems = $('[id^="' + inquiryId + '_"] input[type="checkbox"');
    //} else {
    //    elems = inquiryId;
    //}
    var elems = $('[id^="' + inquiryId + '_"] input[type="checkbox"]');
    var result = [];
    elems.each(function(index, elem) {
        if ($(this).puicheckbox('isChecked')) {
            //var id = elem.val();
            //result.push(+id);
            result.push($(this).val());
        }
    });
    return result; 
}


function _createAutocomplete(context,value) {
    var autocompleteName = 'text_' + value.inquiry.id;
    var autocompleteId = value.inquiry.id + '_autocomplete';
    var autocompleteHiddenId = value.inquiry.id + '_autocomplete_hidden';
    var autocompleteHidden = $('<input>', {
        "type": "hidden",
        "name": autocompleteName,
        "id": autocompleteHiddenId,
        "disabled": !value.inquiry.disabled,
        "value": (value.textValue != null ? value.textValue : '')
    }); //$('<input type="hidden" name="' + autocompleteName + '" id="' + autocompleteHiddenId + '" value=""/>');
    //var singleLineText = $('<input type="text" class="ctsms-control" name="' + singleLineTextName + '" id="' + singleLineTextId + '"/>', { "value": value.textValue }).puiinputtext();
    var autocomplete = $('<input>', {
        "type": "text",
        "class": "ctsms-control-larger",
        "name": autocompleteName,
        "id": autocompleteId,
        "value": (value.textValue != null ? value.textValue : '')
    });
    return [ autocompleteHidden, autocomplete ];
}
function _initAutocomplete(context,value,content) {
    var autocompleteId = value.inquiry.id + '_autocomplete';
    var options = $.extend( true, {}, getFieldValueAutoCompleteConfig(value.inquiry.field) );
    if (!value.inquiry.disabled && value.hasJsVar) {
        options.select = function(event, item) {
            FieldCalculation.autoCompleteOnChange(value);
        };
    }
    $('#' + autocompleteId).puiautocomplete(options);
    if (value.inquiry.disabled) {
        $('#' + autocompleteId).puiautocomplete('disable');
    } else if (value.hasJsVar && !value.inquiry.field.strict) {
        $('#' + autocompleteId).on('change', function(event) {
            FieldCalculation.autoCompleteOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.autoCompleteOnChange(value);
        });
    }
    $('#' + autocompleteId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });
}

function setAutocompleteVal(inquiryId,text) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_autocomplete');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_autocomplete');
    elem.val(text);
}

function getAutocompleteVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_autocomplete');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_autocomplete');
    return elem.val();
}

function _createSketchpadButton(buttonId, styleClass, tooltipText) {
    var content = $('<td/>');
    var button = $('<div id="' + buttonId + '" class="' + styleClass + '"/>');
    content.append(button);
    button.puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: tooltipText
    });
    content.off().on('mouseenter', '#' + buttonId, null, function(event) {
        $('#' + buttonId).puitooltip('show');
    }).on('mouseleave', '#' + buttonId, null, function(event) {
        $('#' + buttonId).puitooltip('hide');
    });    
    return content;
}

function _createSketchpad(context,value) {
    var sketchpadInputName = 'ink_' + value.inquiry.id;
    var sketchpadInputId = value.inquiry.id + '_sketchpad_input';
    var sketchpadDivId = value.inquiry.id + '_sketchpad';
    var sketchpadInput = $('<input>', {
        "type": "hidden",
        "name": sketchpadInputName,
        "id": sketchpadInputId,
        "value": (value.inkValue != null ? value.inkValue : '')
    });
    var style = '';
    var sketchpadDiv = $('<div class="sketchpad" id="' + sketchpadDivId + '" style="width:' +
        (value.inquiry.field.width == null ? '' : value.inquiry.field.width) + 'px;height:' +
        (value.inquiry.field.height == null ? '' : value.inquiry.field.height) + 'px;' + style + '"/>');

    var content = $('<span/>');
    if (!value.inquiry.disabled) {    
        var buttonRow = $('<tr/>');
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_regionToggler", "sketch-region-toggler-off", context.sketchToggleRegionTooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_drawEraseMode", "sketch-draw-mode", context.sketchDrawModeTooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_undo", "sketch-undo-disabled", context.sketchUndoTooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_redo", "sketch-redo-disabled", context.sketchRedoTooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_clear", "sketch-clear-disabled", context.sketchClearTooltip));
        buttonRow.append($('<td/>').append(document.createTextNode(' ')));
        buttonRow.append($('<td/>').append('<input type="text" id="' + sketchpadDivId + '_colorPicker' + '"/>'));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penWidth0", "sketch-pen-width-0-disabled", context.sketchPenWidth0Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penWidth1", "sketch-pen-width-1-disabled", context.sketchPenWidth1Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penWidth2", "sketch-pen-width-2", context.sketchPenWidth2Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penWidth3", "sketch-pen-width-3-disabled", context.sketchPenWidth3Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penOpacity0", "sketch-pen-opacity-0", context.sketchPenOpacity0Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penOpacity1", "sketch-pen-opacity-1-disabled", context.sketchPenOpacity1Tooltip));
        buttonRow.append(_createSketchpadButton(sketchpadDivId + "_penOpacity2", "sketch-pen-opacity-2-disabled", context.sketchPenOpacity2Tooltip));
    
        var table = $('<table class="sketch-toolbar-table"/>');
        table.append(buttonRow);
    
        content.append(table);
    }
    content.append(sketchpadDiv);
    
    return [ sketchpadInput, content ];
}
function _initSketchpad(context,value,content) {

    var sketchpadInputId = value.inquiry.id + '_sketchpad_input';
    var sketchpadDivId = value.inquiry.id + '_sketchpad';
    var args = [ value.inkValue == null ? '' : value.inkValue,
        sketchpadInputId,
        sketchpadDivId,
        value.inquiry.field.width == null ? 0 : value.inquiry.field.width,
        value.inquiry.field.height == null ? 0 : value.inquiry.field.height,
        context.ctsmsBaseUri + 'inputfieldimage?inputfieldid=' + value.inquiry.field.id,
        !value.inquiry.disabled, // enabled,
        value.hasJsVar ? 'FieldCalculation.sketchOnChange("'+ value.inquiry.jsVariableName +'",' + value.index + ',this)' : null, //onChange,
        null // strokesId -> region edit on if provided
    ];
    for (var i = 0; i < value.inquiry.field.selectionSetValues.length; i++) {
        var selectionSetValue = value.inquiry.field.selectionSetValues[i];
        args.push(selectionSetValue.inkRegions);
    }    
    return Sketch.initSketch.apply(this,args);
}


function _createSpinner(context,value) {
    var spinnerName = 'long_' + value.inquiry.id;
    var spinnerId = value.inquiry.id + '_spinner';
    var spinnerHiddenId = value.inquiry.id + '_spinner_hidden';
    var spinnerHidden = $('<input type="hidden" name="' + spinnerName + '" id="' + spinnerHiddenId + '" value="' + (value.longValue != null ? value.longValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');    
    //var singleLineText = $('<input type="text" class="ctsms-control" name="' + singleLineTextName + '" id="' + singleLineTextId + '"/>', { "value": value.textValue }).puiinputtext();
    var spinner = $('<input type="text" class="ctsms-spinner" name="' + spinnerName + '" id="' + spinnerId + '" value="' + (value.longValue != null ? value.longValue : '') + '"/>');

    return [ spinnerHidden, spinner ];
}
function _initSpinner(context,value,content) {
    var spinnerId = value.inquiry.id + '_spinner';
    $('#' + spinnerId).puispinner({
    
    });
    if (value.inquiry.disabled) {
        $('#' + spinnerId).puispinner('disable');
    } else if (value.hasJsVar) {
        $('#' + spinnerId).on('change', function(event) {
            FieldCalculation.integerOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.integerOnChange(value);
        }); 
    }
    $('#' + spinnerId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });    
}

function setSpinnerVal(inquiryId,val) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_spinner');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_spinner');
    elem.val(val);
}
function getSpinnerVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_spinner');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_spinner');
    //var val = elem.val();
    //return (isNaN(parseInt(val)) ? val : parseInt(val));
    return elem.val();
}

function _createDecimal(context,value) {
    var decimalName = 'float_' + value.inquiry.id;
    var decimalId = value.inquiry.id + '_decimal';
    var decimalHiddenId = value.inquiry.id + '_decimal_hidden';
    var decimalHidden = $('<input type="hidden" name="' + decimalName + '" id="' + decimalHiddenId + '" value="' + (value.floatValue != null ? value.floatValue : '') + '"' + (!value.inquiry.disabled ? ' disabled' : '') + '/>');        
    //var singleLineText = $('<input type="text" class="ctsms-control" name="' + singleLineTextName + '" id="' + singleLineTextId + '"/>', { "value": value.textValue }).puiinputtext();
    var decimal = $('<input type="text" class="ctsms-control-float" name="' + decimalName + '" id="' + decimalId + '" value="' + (value.floatValue != null ? value.floatValue : '') + '"/>').puiinputtext({
    
    });
    //if (value.inquiry.disabled) {
    //    decimal.puiinputtext('disable');
    //}        
    //decimal.puitooltip({
    //    my: 'left bottom',
    //    at: 'left top',  
    //    content: _getTooltipText(context,value) //context.probandDobTooltip
    //});
    return [ decimalHidden, decimal ];
}
function _initDecimal(context,value,content) {
    var decimalId = value.inquiry.id + '_decimal';
    if (value.inquiry.disabled) {
        $('#' + decimalId).puiinputtext('disable');
    } else if (value.hasJsVar) {
        $('#' + decimalId).on('change', function(event) {
            FieldCalculation.floatOnChange(value);
        }).on('keyup', function(event) {
            FieldCalculation.floatOnChange(value);
        }); 
    }  
    $('#' + decimalId).puitooltip({
        my: 'left bottom',
        at: 'left top',  
        content: _getTooltipText(context,value) //context.probandDobTooltip
    });  
}

function setDecimalVal(inquiryId,val) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_decimal');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_decimal');
    elem.val(val);
}
function getDecimalVal(inquiryId) {
    //var elem;
    //if($.type(inquiryId) === "string") {
    //    elem = $('#' + inquiryId + '_decimal');
    //} else {
    //    elem = inquiryId;
    //}
    var elem = $('#' + inquiryId + '_decimal');
    return elem.val().replace(/,/,'.');
    //return (isNaN(parseFloat(val)) ? val : parseFloat(val));
}

function _updateInquiryPbar(context) {
    
    var value = 0;
    if (context.trial != null && context.trial._activeInquiryCount > 0) {
        value = Math.round((context.trial._savedInquiryCount / context.trial._activeInquiryCount) * 100.0);
    }
    $('#inquiry_pbar').puiprogressbar({
        labelTemplate: sprintf(context.inquiriesPbarTemplate, +context.trial._savedInquiryCount, +context.trial._activeInquiryCount),
        value: value
        //_postedInquiryCount
    })    
    
}

function _saveEnteredData(context,ajaxContext,callback,ui,updateUi) {
    if (!context.init) {
        context.checkForm = false;
        if (_sanitizeForm(context)) {
            $.ajax({
                type: "POST",
                url: context.uriBase + '/inquiry/savepage',
                data: $('#form').serialize(),
                //dataType: "json",
                context: ajaxContext,
                error: function(jqXHR, textStatus, errorThrown) {
                    $.ajaxSettings.error(jqXHR, textStatus, errorThrown);
                    if (updateUi != null) {
                        updateUi(true);
                    }
                },
                success: function(data) {
                    context.trial = data;
                    setMessages('warn',null);
                    _loadPage(context,ajaxContext,callback,ui,updateUi);
                }
            });
        }
    } else {
        _loadPage(context,ajaxContext,callback,ui,updateUi);
        //callback(ajaxContext);
    }
}

function _loadPage(context,ajaxContext,callback,ui,updateUi) {
                $.ajax({
                    //type: "GET",
                    url: context.uriBase + '/inquiries',
                    data: { rows: ui.rows, first: ui.first, load_all_js_values: (context.init ? 1 : 0) },
                    //dataType: "json",
                    context: ajaxContext,
                    success: function(data) {
                        context.trial = data.trial;
                        context.inquiryStatusVar = {
                            i: 0,
                            first: true,
                            last:null,
                            rows: data.rows.length,
                            //totalRecords: data.paginator.total_count,
                            category: null,
                            categoryFields: [],
                            fieldsToInit: [],
                            posted: 0,
                            toPost: 0
                        };
                        if(this.options.paginator) {
                            this.options.paginator.totalRecords = data.paginator.total_count;
                        };
                        //$('#form > :input[id*="checkbox_hidden_"]').remove();
                        //_getFormFields('date').remove();
                        callback.call(this, data.rows);
                        if (context.apiError != null) {
                            setMessages('warn', context.apiError ); //{summary: 'Message Title', detail: context.apiError});
                        }
                        var fieldCalculationArgs = {};
                        fieldCalculationArgs[AJAX_OPERATION_SUCCESS] = true;
                        fieldCalculationArgs[AJAX_INPUT_FIELD_VARIABLE_VALUES_BASE64] = data.js_rows_base64;
                        
                        fieldCalculationArgs[AJAX_INPUT_FIELD_PROBAND_BASE64] = context.probandBase64;
                        fieldCalculationArgs[AJAX_INPUT_FIELD_TRIAL_BASE64] = context.trialBase64;
                        fieldCalculationArgs[AJAX_INPUT_FIELD_PROBAND_ADDRESSES_BASE64] = context.probandAddressesBase64;
                        fieldCalculationArgs[AJAX_INPUT_FIELD_LOCALE] = context.lang;
                        
                        if (context.init) {
                            FieldCalculation.handleInitInputFieldVariables(null,null,fieldCalculationArgs);
                            context.init = false;
                        } else {
                            FieldCalculation.handleUpdateInputFieldVariables(null,null,fieldCalculationArgs);
                        }
                        if (updateUi != null) {
                           updateUi(false);
                        }
                        _updateInquiryPbar(context);
                        hideWaitDlg();
                    }
                });
            }

function _getInquiryId(element) {
    return element.id.match(idRegexp)[2];
}

function _getTooltipText(context, value) {
    var result = value.inquiry.field.fieldType.name + ' ';
    if (value.inquiry.optional) {
        result += context.optionalLabel;
    } else {
        result += context.requiredLabel;
    }
    result += '.';
    var validationErrorMsg = value.inquiry.field.validationErrorMsg;
    if (validationErrorMsg != null && validationErrorMsg.length > 0) {
        result += ' ' + validationErrorMsg;
    }
    return result;
}

function _sanitizeForm(context) {

    //$('#form :input[id$="checkbox"]').each(function(index,element){
    //    var inquiryId = _getInquiryId(element);
    //    setCheckboxVal(inquiryId,getCheckboxVal(inquiryId));
    //});
    
    if (context.checkForm) {
        if (context.trial._savedInquiryCount < context.trial._activeInquiryCount
            && (context.trial._postedInquiryCount + (context.saveAllPages ? 0 : context.trial._savedInquiryCount) + context.inquiryStatusVar.toPost) < context.trial._activeInquiryCount) {
            $('#incomplete_dlg').puidialog('show');
            return false;
        }
    //} else {
    //    context.checkForm = true;
    }
    
    showWaitDlg();
    
    return true; // return false to cancel form action
}

//function _isJsVar(value) {
//    return value.inquiry.jsVariableName != null && value.inquiry.jsVariableName.length > 0;
//}

//function resetForm() {
//    
//    $('#messages').puimessages('clear');
//    
//}

