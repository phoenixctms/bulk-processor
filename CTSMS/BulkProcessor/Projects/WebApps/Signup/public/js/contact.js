
function initPrimeUI(context) {

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: 248,
        transitionInterval: 10000
    });

    $('#country_name').puiautocomplete(getCountryNameAutoCompleteConfig());
    $('#country_name').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressCountryNameTooltip
    });

    $('#province').puiautocomplete(getProvinceAutoCompleteConfig('country_name'));
    $('#province').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressProvinceTooltip
    });

    $('#zip_code').puiautocomplete(getZipCodeAutoCompleteConfig('country_name','province','city_name'));
    $('#zip_code').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressZipCodeTooltip
    });

    $('#city_name').puiautocomplete(getCityNameAutoCompleteConfig('country_name','province','zip_code'));
    $('#city_name').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAddressCityNameTooltip
    });

    $('#street_name').puiautocomplete(getStreetNameAutoCompleteConfig('country_name','province','city_name'));
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
        setMessages('warn', context.apiError );
    }

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });

    $('#save_next_btn').puibutton({

        icon: 'fa-angle-right',
        iconPos: 'right'
    });
    $('#save_done_btn').puibutton({

        icon: 'fa-angle-double-right',
        iconPos: 'right'
    });

    $('#address_panel').puipanel();
    $('#contact_details_panel').puipanel();

}

function _sanitizeForm(context) {

    showWaitDlg();
    return true;
}
