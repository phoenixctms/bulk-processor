


function initPrimeUI(context) {

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: 280, //313,
        transitionInterval: 10000
    });

    $('#prefixed_title_1').puiautocomplete(getTitleAutoCompleteConfig());
    $('#prefixed_title_1').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandPrefixedTitlesTooltip
    });
    $('#prefixed_title_2').puiautocomplete(getTitleAutoCompleteConfig());
    $('#prefixed_title_3').puiautocomplete(getTitleAutoCompleteConfig());
    
    $('#first_name').puiinputtext();
    $('#first_name').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandFirstNameTooltip
    });
    
    $('#last_name').puiinputtext();
    $('#last_name').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandLastNameTooltip
    });

    $('#postpositioned_title_1').puiautocomplete(getTitleAutoCompleteConfig());
    $('#postpositioned_title_1').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandPostpositionedTitlesTooltip
    });
    $('#postpositioned_title_2').puiautocomplete(getTitleAutoCompleteConfig());
    $('#postpositioned_title_3').puiautocomplete(getTitleAutoCompleteConfig());
    
    $('#gender').puidropdown({
            styleClass: 'ctsms-control'
    });
    $('#gender').parent().parent().find('.ui-inputtext').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandGenderTooltip
    });  

    //$('#dob_picker').children('input').puiinputtext().addClass('ctsms-control-date');
    //$('#dob_picker').children('input').puitooltip({
    //    content: context.probandDobTooltip
    //});
    //$('#dob_picker')[0].setDate(parseDate(context.session.dob));
    $('#dob').puidatepicker({
        yearRange: "-120:+0"
    });
    $('#dob').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandDobTooltip
    });
    
    $('#citizenship').puiautocomplete(getCountryNameAutoCompleteConfig());
    $('#citizenship').puitooltip({
        my: 'left bottom',
        at: 'left top',        
        content: context.probandCitizenshipTooltip
    });
    
    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError ); //{summary: 'Message Title', detail: context.apiError});
    }

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });
    //$('#reset_btn').puibutton({
    //    icon: 'fa-close',
    //    click: function(event) {
    //        resetForm();
    //    }
    //});
    $('#save_next_btn').puibutton({
        //icon: 'fa-save'
        icon: 'fa-angle-right',
        iconPos: 'right'        
    });    
    //$('#save_done_btn').puibutton({
    //    icon: 'fa-save'
    //});   
    
    $('#proband_panel').puipanel(); //.puifieldset();

}

function _sanitizeForm(context) {
    //var result = true;
    //result = result && _sanitizeDatePicker('dob', 'dob_picker', true);
    //return result;
    showWaitDlg();
    
    //_sanitizeDatePicker('dob_picker', 'dob');
    return true;
}

//function resetForm() {
//    
//    $('#prefixed_title_1').val(null);
//    $('#prefixed_title_2').val(null);
//    $('#prefixed_title_3').val(null);
//    $('#first_name').val(null);
//    $('#last_name').val(null);
//    $('#postpositioned_title_1').val(null);
//    $('#postpositioned_title_2').val(null);
//    $('#postpositioned_title_3').val(null);
//    
//    //$('#gender').val('');
//    $('#gender').puidropdown('selectValue','');
//    
//    //$('#proband_dob').val(null);
//    //$('#dob_picker')[0].setDate(null);
//    $('#dob_picker').puidatepicker('setDate', null);
//    
//    $('#citizenship').val(null);
//    
//    $('#messages').puimessages('clear');
//    
//    //$('#form')[0].each(function() { this.reset(); });
//    //document.getElementById('form').reset();
//    //document.getElementById('dob').value = null;
//}
