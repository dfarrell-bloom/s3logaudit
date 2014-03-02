
$(document).ready( function(){ 
    // console.log( window.location )
    $("nav a").each( function() {
        var href = $(this).attr('href')
        if( href == window.location.href || 
            href == window.location.pathname  || 
            window.location.pathname.search( href ) == 0
        ){
            $(this).addClass( 'current' )
            // console.log( this )
        } else {
            // console.log( href + " not in ( " + window.location.href + " , " + window.location.pathname )
        }
    })  
})
