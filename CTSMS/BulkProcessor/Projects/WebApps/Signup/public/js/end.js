


function initPrimeUI(context) {
    
    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: 300, //313,
        transitionInterval: 10000
    }); 
    
    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError ); //{summary: 'Message Title', detail: context.apiError});
    }

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });
    $('#probandletter_btn').puibutton({
        icon: 'fa-file-pdf-o',
        click: function(event) {
            showWaitDlg();
            window.open(context.uriBase + '/end/probandletterpdf', '_blank');
            hideWaitDlg();
        }
    });
    $('#inquiryforms_btn').puibutton({
        icon: 'fa-file-pdf-o',
        click: function(event) {
            showWaitDlg();
            window.open(context.uriBase + '/end/inquiryformspdf', '_blank');
            hideWaitDlg();
        }
    });    
    $('#finish_btn').puibutton({
        icon: 'fa-sign-out',
        iconPos: 'right'
    });    
    //$('#save_done_btn').puibutton({
    //    icon: 'fa-save'
    //});   
    
    //$('#thank_you_panel').puipanel(); //.puifieldset();
    
}

function _sanitizeForm(context) {
    //var result = true;
    //result = result && _sanitizeDatePicker('dob', 'dob_picker', true);
    //return result;
    showWaitDlg();
    
    //_sanitizeDatePicker('dob_picker', 'dob');
    return true;
}
