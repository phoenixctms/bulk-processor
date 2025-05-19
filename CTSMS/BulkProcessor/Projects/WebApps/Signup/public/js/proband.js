


function initPrimeUI(context) {

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        //panelHeight: 180,
        panelHeight: '20%',
        transitionInterval: 10000
    });

    $('#proband_agreed').puicheckbox();
    if (context.probandCreated && $('#proband_agreed').puicheckbox('isChecked')) {
        $('#proband_agreed').puicheckbox('disable');
    }
    $('#proband_agreed').parent().parent().puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.probandAgreedTooltip
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
        setMessages('warn', context.apiError );
    }

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });






    $('#save_next_btn').puibutton({

        icon: 'fa-angle-right',
        iconPos: 'right'
    });




    $('#express_consent_panel').puipanel();
    $('#proband_panel').puipanel();

}

function _sanitizeForm(context) {



    showWaitDlg();


    return true;
}



























