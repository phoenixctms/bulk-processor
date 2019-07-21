


function initPrimeUI(context) {

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: 248, //313,
        transitionInterval: 10000
    });

    $('#country_name').puiautocomplete(getCountryNameAutoCompleteConfig());
    $('#country_name').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressCountryNameTooltip
    });

    $('#zip_code').puiautocomplete(getZipCodeAutoCompleteConfig('country_name','city_name'));
    $('#zip_code').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressZipCodeTooltip
    });

    $('#city_name').puiautocomplete(getCityNameAutoCompleteConfig('country_name','zip_code'));
    $('#city_name').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressCityNameTooltip
    });

    $('#street_name').puiautocomplete(getStreetNameAutoCompleteConfig('country_name','city_name'));
    $('#street_name').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressStreetNameTooltip
    });

    $('#house_number').puiinputtext();
    $('#house_number').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressHouseNumberTooltip
    });

    $('#entrance').puiinputtext();
    $('#entrance').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressEntranceTooltip
    });

    $('#door_number').puiinputtext();
    $('#door_number').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressDoorNumberTooltip
    });

    $('#phone').puiinputtext();
    $('#phone').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandPhoneTooltip
    });

    $('#email').puiinputtext();
    $('#email').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandEmailTooltip
    });

    $('#email_notify').puicheckbox();
    $('#email_notify').parent().parent().puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandEmailNotifyTooltip
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
    $('#save_done_btn').puibutton({
        //icon: 'fa-save'
        icon: 'fa-angle-double-right',
        iconPos: 'right'
    });

    $('#address_panel').puipanel();
    $('#contact_details_panel').puipanel(); //.puifieldset();

}

function _sanitizeForm(context) {
    //$.datepicker._updateAlternate(inst);
    //console.log($('#email_notify').val());
    //if ($('#email_notify').puicheckbox("isChecked")) {
    //    console.log("checked");
    //    $('#email_notify').val("true");
    //} else {
    //    console.log("NOT checked");
    //    $('#email_notify').val("");
    //}
    //console.log($('#email_notify').val());
    //alert();
    showWaitDlg();
    return true; // return false to cancel form action
}

//function resetForm() {
//
//    $('#country_name').val(null);
//    $('#zip_code').val(null);
//    $('#city_name').val(null);
//
//    $('#street_name').val(null);
//
//    $('#house_number').val(null);
//
//    $('#entrance').val(null);
//
//    $('#door_number').val(null);
//
//    $('#phone').val(null);
//
//    $('#email').val(null);
//
//    $('#messages').puimessages('clear');
//
//    //$('#form')[0].each(function() { this.reset(); });
//    //document.getElementById('form').reset();
//    //document.getElementById('dob').value = null;
//}
