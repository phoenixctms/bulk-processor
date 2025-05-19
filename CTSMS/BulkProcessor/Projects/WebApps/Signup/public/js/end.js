


function initPrimeUI(context) {

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: (window.innerWidth < 940 ? window.innerWidth / 940 : 1.0) * 300,
        transitionInterval: 10000
    });

    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError );
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






}

function _sanitizeForm(context) {



    showWaitDlg();


    return true;
}
